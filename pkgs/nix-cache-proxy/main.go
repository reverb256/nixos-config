// nix-cache-proxy: Lightweight reverse proxy for nix-serve-ng with
// pull-through cache warming, Prometheus metrics, and health checks.
//
// Listens on --listen (default :50000), proxies to nix-serve-ng on
// --backend (default :50001). On cache miss (404 from backend), triggers
// async nix copy from upstream substituters so the next request hits.
//
// Endpoints:
//   GET /health           → JSON store stats
//   GET /metrics          → Prometheus text format
//   POST /api/warm?path=  → Force cache warming for a store path
//   GET /*                → Proxied to nix-serve-ng

package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// ── byte counting response writer ──────────────────────────────────

type countingWriter struct {
	http.ResponseWriter
	bytes *atomic.Int64
}

func (cw *countingWriter) Write(b []byte) (int, error) {
	n, err := cw.ResponseWriter.Write(b)
	cw.bytes.Add(int64(n))
	return n, err
}

// ── Metrics ────────────────────────────────────────────────────────

type Metrics struct {
	Requests     atomic.Int64
	CacheHits    atomic.Int64
	CacheMisses  atomic.Int64
	CacheFills   atomic.Int64
	FillErrors   atomic.Int64
	BytesServed  atomic.Int64
	LastFillTime time.Time
	LastFillPath string
	mu           sync.RWMutex
}

func (m *Metrics) recordHit() {
	m.CacheHits.Add(1)
	m.Requests.Add(1)
}

func (m *Metrics) recordMiss() {
	m.CacheMisses.Add(1)
	m.Requests.Add(1)
}

func (m *Metrics) recordFill(path string) {
	m.CacheFills.Add(1)
	m.mu.Lock()
	m.LastFillTime = time.Now()
	m.LastFillPath = path
	m.mu.Unlock()
}

func (m *Metrics) recordFillError() {
	m.FillErrors.Add(1)
}

// ── Store info ─────────────────────────────────────────────────────

type StoreInfo struct {
	StorePath     string `json:"store_path"`
	StoreSize     string `json:"store_size"`
	StoreEntries  int    `json:"store_entries"`
	UptimeSeconds int64  `json:"uptime_seconds"`
}

var startTime = time.Now()

func getStoreInfo(nixStorePath string) StoreInfo {
	info := StoreInfo{
		StorePath:     nixStorePath,
		UptimeSeconds: int64(time.Since(startTime).Seconds()),
	}
	entries, _ := filepath.Glob(filepath.Join(nixStorePath, "*"))
	info.StoreEntries = len(entries)
	cmd := exec.Command("du", "-sh", nixStorePath)
	out, err := cmd.Output()
	if err == nil {
		info.StoreSize = strings.TrimSpace(string(out))
	}
	return info
}

// ── Async cache fill ───────────────────────────────────────────────

var upstreams = []string{
	"https://cache.nixos.org",
	"https://nix-community.cachix.org",
	"https://reverb-os.cachix.org",
	"https://maplespike.cachix.org",
	"https://ezkea.cachix.org",
	"https://nix-gaming.cachix.org",
}

// extractStorePath reconstructs a /nix/store/<hash>-name path from a
// narinfo/nar request path or a full store path.
func extractStorePath(requestPath, nixStore string) string {
	// If this is already a full store path, return it directly
	if strings.HasPrefix(requestPath, nixStore+"/") {
		if _, err := os.Stat(requestPath); err == nil {
			return requestPath
		}
		return ""
	}
	// Parse narinfo-style path: /<hash>.narinfo or /nar/<hash>.nar
	base := filepath.Base(requestPath)
	hash := strings.TrimSuffix(base, ".narinfo")
	if hash == base {
		hash = strings.TrimSuffix(base, ".nar")
		if hash == base {
			return ""
		}
	}
	entries, err := filepath.Glob(filepath.Join(nixStore, hash+"*"))
	if err != nil || len(entries) == 0 {
		return ""
	}
	return entries[0]
}

var fillQueue = make(chan string, 100)

func startFillWorker(nixStore string) {
	go func() {
		for path := range fillQueue {
			log.Printf("[fill] warming %s", path)
			success := false
			for _, upstream := range upstreams {
				cmd := exec.Command("nix", "copy",
					"--from", upstream,
					path,
				)
				cmd.Stdout = os.Stdout
				cmd.Stderr = os.Stderr
				if err := cmd.Run(); err == nil {
					success = true
					break
				}
			}
			if success {
				metrics.recordFill(path)
				log.Printf("[fill] warmed %s", path)
			} else {
				metrics.recordFillError()
				log.Printf("[fill] FAILED to warm %s from any upstream", path)
			}
		}
	}()
}

func triggerAsyncFill(requestPath, nixStore string) {
	hash := extractStorePath(requestPath, nixStore)
	if hash == "" {
		return
	}
	select {
	case fillQueue <- hash:
	default:
	}
}

// ── Handlers ───────────────────────────────────────────────────────

var metrics = &Metrics{}

func healthHandler(nixStore string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		info := getStoreInfo(nixStore)
		metrics.mu.RLock()
		reqs := metrics.Requests.Load()
		hits := metrics.CacheHits.Load()
		hitRate := 0.0
		if reqs > 0 {
			hitRate = float64(hits) / float64(reqs)
		}
		infoJSON := map[string]interface{}{
			"store":          info,
			"cache_hits":     hits,
			"cache_misses":   metrics.CacheMisses.Load(),
			"cache_fills":    metrics.CacheFills.Load(),
			"fill_errors":    metrics.FillErrors.Load(),
			"requests_total": reqs,
			"bytes_served":   metrics.BytesServed.Load(),
			"last_fill_path": metrics.LastFillPath,
			"hit_rate":       hitRate,
		}
		metrics.mu.RUnlock()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(infoJSON)
	}
}

func metricsHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		fmt.Fprintf(w, "# HELP nix_cache_requests_total Total requests served\n# TYPE nix_cache_requests_total counter\nnix_cache_requests_total %d\n", metrics.Requests.Load())
		fmt.Fprintf(w, "# HELP nix_cache_hits_total Cache hit count\n# TYPE nix_cache_hits_total counter\nnix_cache_hits_total %d\n", metrics.CacheHits.Load())
		fmt.Fprintf(w, "# HELP nix_cache_misses_total Cache miss count\n# TYPE nix_cache_misses_total counter\nnix_cache_misses_total %d\n", metrics.CacheMisses.Load())
		fmt.Fprintf(w, "# HELP nix_cache_fills_total Async cache fills triggered\n# TYPE nix_cache_fills_total counter\nnix_cache_fills_total %d\n", metrics.CacheFills.Load())
		fmt.Fprintf(w, "# HELP nix_cache_fill_errors_total Failed cache fills\n# TYPE nix_cache_fill_errors_total counter\nnix_cache_fill_errors_total %d\n", metrics.FillErrors.Load())
		fmt.Fprintf(w, "# HELP nix_cache_bytes_served_total Bytes served\n# TYPE nix_cache_bytes_served_total counter\nnix_cache_bytes_served_total %d\n", metrics.BytesServed.Load())
		fmt.Fprintf(w, "# HELP nix_cache_uptime_seconds Uptime in seconds\n# TYPE nix_cache_uptime_seconds gauge\nnix_cache_uptime_seconds %d\n", int64(time.Since(startTime).Seconds()))
	}
}

func warmHandler(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Query().Get("path")
	if path == "" {
		http.Error(w, "missing ?path=<store-path>", http.StatusBadRequest)
		return
	}
	// Pass full store path directly to fill queue
	select {
	case fillQueue <- path:
	default:
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "queued", "path": path})
}

// ── Main ───────────────────────────────────────────────────────────

func main() {
	listen := flag.String("listen", ":50000", "Listen address")
	backend := flag.String("backend", "http://127.0.0.1:50001", "nix-serve-ng backend")
	nixStore := flag.String("nix-store", "/nix/store", "Path to Nix store")
	flag.Parse()

	backendURL, err := url.Parse(*backend)
	if err != nil {
		log.Fatalf("invalid backend URL: %v", err)
	}

	startFillWorker(*nixStore)

	proxy := httputil.NewSingleHostReverseProxy(backendURL)

	// Single ModifyResponse: track hits/misses, trigger fills on 404,
	// count bytes for chunked and non-chunked responses.
	proxy.ModifyResponse = func(resp *http.Response) error {
		if resp.StatusCode == http.StatusOK {
			metrics.recordHit()
		}
		if resp.StatusCode == http.StatusNotFound {
			metrics.recordMiss()
			if resp.Request != nil {
				triggerAsyncFill(resp.Request.URL.Path, *nixStore)
			}
		}
		// Wire up byte counting for both chunked and fixed-length responses
		resp.Body = &countingReadCloser{
			ReadCloser: resp.Body,
			bytes:      &metrics.BytesServed,
		}
		return nil
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler(*nixStore))
	mux.HandleFunc("/metrics", metricsHandler())
	mux.HandleFunc("/api/warm", warmHandler)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		proxy.ServeHTTP(w, r)
	})

	srv := &http.Server{
		Addr:         *listen,
		Handler:      mux,
		ReadTimeout:  60 * time.Second,
		WriteTimeout: 300 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	log.Printf("nix-cache-proxy listening on %s, backend %s", *listen, *backend)
	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

// countingReadCloser wraps an io.ReadCloser and counts bytes read.
// Handles chunked encoding by counting raw bytes on the wire.
type countingReadCloser struct {
	io.ReadCloser
	bytes *atomic.Int64
}

func (c *countingReadCloser) Read(b []byte) (int, error) {
	n, err := c.ReadCloser.Read(b)
	c.bytes.Add(int64(n))
	return n, err
}
