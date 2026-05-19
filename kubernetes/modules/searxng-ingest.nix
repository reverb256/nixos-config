{cluster,
  nexusPreferredAffinity, ...}: let
  labels = {
    app = "searxng-ingest";
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  # ── Python script: scan Valkey, evaluate quality, ingest to Qdrant ──
  ingestScript = ''
    import json
    import os
    import sys
    import time
    import urllib.request
    import urllib.parse
    import hashlib
    from datetime import datetime, timezone

    VALKEY_HOST = os.environ.get("VALKEY_HOST", "valkey.search.svc.cluster.local")
    VALKEY_PORT = int(os.environ.get("VALKEY_PORT", "6379"))
    VALKEY_DB = int(os.environ.get("VALKEY_DB", "0"))

    QDRANT_URL = os.environ.get("QDRANT_URL", "http://qdrant.ai-inference.svc.cluster.local:6333")
    QDRANT_COLLECTION = os.environ.get("QDRANT_COLLECTION", "searxng-results")

    GATEWAY_URL = os.environ.get("GATEWAY_URL", "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080")
    EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "BidirLM/BidirLM-Omni-2.5B-Embedding")
    EMBEDDING_DIM = int(os.environ.get("EMBEDDING_DIM", "2048"))

    QUALITY_THRESHOLD = float(os.environ.get("QUALITY_THRESHOLD", "0.6"))
    BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "10"))
    FETCH_TIMEOUT = int(os.environ.get("FETCH_TIMEOUT", "15"))

    # Trusted domains get a quality boost
    TRUSTED_DOMAINS = {
        "github.com": 0.15, "stackoverflow.com": 0.15, "docs.python.org": 0.12,
        "developer.mozilla.org": 0.12, "nixos.org": 0.12, "wikipedia.org": 0.10,
        "arxiv.org": 0.12, "pubmed.ncbi.nlm.nih.gov": 0.12, "huggingface.co": 0.10,
        "pypi.org": 0.10, "npmjs.com": 0.10, "reddit.com": 0.05,
        "news.ycombinator.com": 0.10, "reuters.com": 0.10,
    }

    # Simple Valkey client using raw TCP (no external deps)
    class ValkeyClient:
        def __init__(self, host, port, db):
            self.host = host
            self.port = port
            self.db = db
            self._conn = None

        def _connect(self):
            import socket
            self._conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self._conn.settimeout(5)
            self._conn.connect((self.host, self.port))
            self._recv()  # Read greeting
            if self.db != 0:
                self._send(["SELECT", str(self.db)])

        def _send(self, args):
            cmd = "*" + str(len(args)) + "\r\n"
            for a in args:
                cmd += "$" + str(len(a)) + "\r\n" + a + "\r\n"
            self._conn.sendall(cmd.encode())

        def _recv(self):
            data = b""
            while True:
                chunk = self._conn.recv(4096)
                if not chunk:
                    break
                data += chunk
                if b"\r\n" in data:
                    break
            return data.decode(errors="replace")

        def scan(self, pattern="*", count=100):
            self._connect()
            self._send(["SCAN", "0", "MATCH", pattern, "COUNT", str(count)])
            resp = self._recv()
            self._conn.close()
            # Parse RESP2: *2\r\n$1\r\n0\r\n*...\r\n
            lines = resp.strip().split("\r\n")
            keys = []
            in_array = False
            array_len = 0
            for i, line in enumerate(lines):
                if line.startswith("*") and i > 0:
                    try:
                        array_len = int(line[1:])
                        if array_len > 0:
                            in_array = True
                            continue
                    except ValueError:
                        pass
                if in_array and array_len > 0:
                    if line.startswith("$"):
                        try:
                            str_len = int(line[1:])
                            if i + 1 < len(lines):
                                keys.append(lines[i + 1])
                                array_len -= 1
                        except ValueError:
                            pass
            return keys

        def get(self, key):
            self._connect()
            self._send(["GET", key])
            resp = self._recv()
            self._conn.close()
            lines = resp.strip().split("\r\n")
            if len(lines) >= 2 and lines[0].startswith("$"):
                try:
                    length = int(lines[0][1:])
                    if length > 0:
                        return lines[1]
                except ValueError:
                    pass
            return None

    def calculate_quality(result):
        """Score a SearXNG result for ingestion quality."""
        score = 0.3  # base score

        # Position bonus (higher results are more relevant)
        position = result.get("position", 10)
        if position <= 3:
            score += 0.2
        elif position <= 5:
            score += 0.1

        # Content length bonus
        content = result.get("content", "")
        if len(content) > 200:
            score += 0.15
        elif len(content) > 100:
            score += 0.1

        # Trusted domain bonus
        url = result.get("url", "")
        for domain, boost in TRUSTED_DOMAINS.items():
            if domain in url:
                score += boost
                break

        # Has title
        if result.get("title"):
            score += 0.05

        # Engine count (results from multiple engines are more reliable)
        engines = result.get("engines", [])
        if len(engines) > 1:
            score += 0.05

        return min(score, 1.0)

    def fetch_content(url):
        """Fetch page content for embedding."""
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "SearXNG-Ingest/1.0"})
            with urllib.request.urlopen(req, timeout=FETCH_TIMEOUT) as resp:
                content_type = resp.getheader("Content-Type", "")
                if "text/html" not in content_type and "text/plain" not in content_type:
                    return None
                raw = resp.read(50000)  # Limit to 50KB
                # Simple HTML stripping
                text = raw.decode("utf-8", errors="replace")
                import re
                text = re.sub(r"<[^>]+>", " ", text)
                text = re.sub(r"\s+", " ", text).strip()
                return text[:10000] if text else None
        except Exception as e:
            print(f"  WARN: Failed to fetch {url}: {e}", file=sys.stderr)
            return None

    def get_embedding(text):
        """Get embedding from AI Gateway."""
        payload = json.dumps({
            "model": EMBEDDING_MODEL,
            "input": text[:8000],  # Truncate to fit context
            "encoding_format": "float",
        }).encode()
        req = urllib.request.Request(
            f"{GATEWAY_URL}/v1/embeddings",
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read())
                return data["data"][0]["embedding"]
        except Exception as e:
            print(f"  WARN: Embedding failed: {e}", file=sys.stderr)
            return None

    def ensure_collection():
        """Create Qdrant collection if it doesn't exist."""
        url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}"
        # Check if exists
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=10) as resp:
                return  # Already exists
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
        # Create collection
        payload = json.dumps({
            "vectors": {
                "size": EMBEDDING_DIM,
                "distance": "Cosine",
            },
            "optimizers_config": {"default_segment_number": 2},
        }).encode()
        req = urllib.request.Request(
            url, data=payload, headers={"Content-Type": "application/json"}, method="PUT",
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            print(f"Created collection {QDRANT_COLLECTION}", file=sys.stderr)

    def upsert_to_qdrant(points):
        """Batch upsert points to Qdrant."""
        if not points:
            return
        url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points?wait=true"
        payload = json.dumps({"points": points}).encode()
        req = urllib.request.Request(
            url, data=payload, headers={"Content-Type": "application/json"}, method="PUT",
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = json.loads(resp.read())
                status = data.get("result", {}).get("status", "unknown")
                print(f"  Upserted {len(points)} points: {status}", file=sys.stderr)
        except Exception as e:
            print(f"  ERROR: Upsert failed: {e}", file=sys.stderr)

    def main():
        print(f"=== SearXNG -> Qdrant Ingestion started at {datetime.now(timezone.utc).isoformat()} ===", file=sys.stderr)
        print(f"  Valkey: {VALKEY_HOST}:{VALKEY_DB}/{VALKEY_DB}", file=sys.stderr)
        print(f"  Qdrant: {QDRANT_URL}/{QDRANT_COLLECTION}", file=sys.stderr)
        print(f"  Quality threshold: {QUALITY_THRESHOLD}", file=sys.stderr)

        ensure_collection()

        client = ValkeyClient(VALKEY_HOST, VALKEY_PORT, VALKEY_DB)

        # Scan for SearXNG result keys (common patterns)
        patterns = ["searxng:*", "search:*", "result:*", "cache:*"]
        all_keys = []
        for pattern in patterns:
            try:
                keys = client.scan(pattern, count=200)
                all_keys.extend(keys)
                print(f"  Found {len(keys)} keys matching '{pattern}'", file=sys.stderr)
            except Exception as e:
                print(f"  WARN: Scan failed for '{pattern}': {e}", file=sys.stderr)

        print(f"  Total keys to evaluate: {len(all_keys)}", file=sys.stderr)

        ingested = 0
        skipped = 0
        points_batch = []

        for key in all_keys:
            try:
                raw = client.get(key)
                if not raw:
                    continue

                try:
                    result = json.loads(raw)
                except json.JSONDecodeError:
                    skipped += 1
                    continue

                # Skip if already ingested (check metadata)
                if result.get("ingested_to_qdrant"):
                    skipped += 1
                    continue

                quality = calculate_quality(result)
                if quality < QUALITY_THRESHOLD:
                    skipped += 1
                    continue

                url = result.get("url", "")
                title = result.get("title", "Untitled")
                content = result.get("content", "")

                # Fetch full content if needed
                if len(content) < 100:
                    full_content = fetch_content(url)
                    if full_content:
                        content = full_content

                if not content or len(content) < 50:
                    skipped += 1
                    continue

                # Generate embedding
                embedding = get_embedding(content)
                if not embedding:
                    skipped += 1
                    continue

                # Create point ID from URL hash
                point_id = hashlib.md5(url.encode()).hexdigest()

                point = {
                    "id": point_id,
                    "vector": embedding,
                    "payload": {
                        "title": title,
                        "url": url,
                        "content": content[:5000],
                        "source": "searxng",
                        "quality_score": quality,
                        "engines": result.get("engines", []),
                        "query": result.get("query", ""),
                        "ingested_at": datetime.now(timezone.utc).isoformat(),
                        "position": result.get("position", 0),
                    },
                }

                points_batch.append(point)
                print(f"  + Queued: {title[:60]}... (quality={quality:.2f})", file=sys.stderr)

                if len(points_batch) >= BATCH_SIZE:
                    upsert_to_qdrant(points_batch)
                    ingested += len(points_batch)
                    points_batch = []

            except Exception as e:
                print(f"  ERROR processing {key}: {e}", file=sys.stderr)
                skipped += 1

        # Flush remaining batch
        if points_batch:
            upsert_to_qdrant(points_batch)
            ingested += len(points_batch)

        print(f"=== Ingestion complete: {ingested} ingested, {skipped} skipped ===", file=sys.stderr)

    if __name__ == "__main__":
        main()
  '';

  # ── Python script: weekly stale document re-indexing ──
  staleReindexScript = ''
    import json
    import os
    import sys
    import time
    import urllib.request
    from datetime import datetime, timezone, timedelta

    QDRANT_URL = os.environ.get("QDRANT_URL", "http://qdrant.ai-inference.svc.cluster.local:6333")
    QDRANT_COLLECTION = os.environ.get("QDRANT_COLLECTION", "searxng-results")
    GATEWAY_URL = os.environ.get("GATEWAY_URL", "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080")
    EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "BidirLM/BidirLM-Omni-2.5B-Embedding")

    STALE_DAYS = int(os.environ.get("STALE_DAYS", "30"))
    BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "20"))

    def scroll_collection():
        """Scroll through all points in the collection."""
        url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/scroll"
        payload = json.dumps({
            "limit": 100,
            "with_payload": True,
            "with_vector": True,
        }).encode()
        points = []
        offset = None
        while True:
            body = json.loads(payload)
            if offset is not None:
                body["offset"] = offset
            req = urllib.request.Request(
                url, data=json.dumps(body).encode(),
                headers={"Content-Type": "application/json"}, method="POST",
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read())
                result = data.get("result", {})
                points.extend(result.get("points", []))
                offset = result.get("next_page_offset")
                if offset is None:
                    break
        return points

    def get_embedding(text):
        """Get embedding from AI Gateway."""
        payload = json.dumps({
            "model": EMBEDDING_MODEL,
            "input": text[:8000],
            "encoding_format": "float",
        }).encode()
        req = urllib.request.Request(
            f"{GATEWAY_URL}/v1/embeddings",
            data=payload,
            headers={"Content-Type": "application/json"}, method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read())
                return data["data"][0]["embedding"]
        except Exception as e:
            print(f"  WARN: Embedding failed: {e}", file=sys.stderr)
            return None

    def fetch_content(url):
        """Re-fetch page content."""
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "SearXNG-Ingest/1.0"})
            with urllib.request.urlopen(req, timeout=15) as resp:
                content_type = resp.getheader("Content-Type", "")
                if "text/html" not in content_type and "text/plain" not in content_type:
                    return None
                raw = resp.read(50000)
                import re
                text = raw.decode("utf-8", errors="replace")
                text = re.sub(r"<[^>]+>", " ", text)
                text = re.sub(r"\s+", " ", text).strip()
                return text[:10000] if text else None
        except Exception as e:
            print(f"  WARN: Failed to fetch {url}: {e}", file=sys.stderr)
            return None

    def upsert_point(point):
        """Upsert a single point to Qdrant."""
        url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points?wait=true"
        payload = json.dumps({"points": [point]}).encode()
        req = urllib.request.Request(
            url, data=payload, headers={"Content-Type": "application/json"}, method="PUT",
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return True
        except Exception as e:
            print(f"  ERROR: Upsert failed: {e}", file=sys.stderr)
            return False

    def main():
        print(f"=== Stale Document Re-indexing started at {datetime.now(timezone.utc).isoformat()} ===", file=sys.stderr)
        print(f"  Collection: {QDRANT_COLLECTION}", file=sys.stderr)
        print(f"  Stale threshold: {STALE_DAYS} days", file=sys.stderr)

        cutoff = datetime.now(timezone.utc) - timedelta(days=STALE_DAYS)

        points = scroll_collection()
        print(f"  Total points in collection: {len(points)}", file=sys.stderr)

        stale_points = []
        for p in points:
            payload = p.get("payload", {})
            ingested_at = payload.get("ingested_at", "")
            if ingested_at:
                try:
                    dt = datetime.fromisoformat(ingested_at.replace("Z", "+00:00"))
                    if dt < cutoff:
                        stale_points.append(p)
                except ValueError:
                    pass

        print(f"  Stale documents: {len(stale_points)}", file=sys.stderr)

        reindexed = 0
        failed = 0

        for p in stale_points:
            payload = p.get("payload", {})
            url = payload.get("url", "")
            title = payload.get("title", "Untitled")

            # Re-fetch content
            new_content = fetch_content(url)
            if not new_content:
                print(f"  - Skipped (unreachable): {title[:60]}...", file=sys.stderr)
                failed += 1
                continue

            # Re-generate embedding
            new_embedding = get_embedding(new_content)
            if not new_embedding:
                print(f"  - Skipped (embedding failed): {title[:60]}...", file=sys.stderr)
                failed += 1
                continue

            # Update point
            point = {
                "id": p["id"],
                "vector": new_embedding,
                "payload": {
                    **payload,
                    "content": new_content[:5000],
                    "reindexed_at": datetime.now(timezone.utc).isoformat(),
                    "reindex_count": payload.get("reindex_count", 0) + 1,
                },
            }

            if upsert_point(point):
                reindexed += 1
                print(f"  + Re-indexed: {title[:60]}...", file=sys.stderr)
            else:
                failed += 1

        print(f"=== Re-indexing complete: {reindexed} re-indexed, {failed} failed ===", file=sys.stderr)

    if __name__ == "__main__":
        main()
  '';
in {
  config.kubernetes.objects = {
    # ── ConfigMap: ingestion scripts ──────────────────────────────
    search.ConfigMap.searxng-ingest-script = {
      metadata.labels = labels;
      data."ingest.py" = ingestScript;
    };

    search.ConfigMap.searxng-stale-reindex-script = {
      metadata.labels = labels;
      data."reindex.py" = staleReindexScript;
    };

    # ── CronJob: scan Valkey and ingest high-quality results ──────
    search.CronJob.searxng-ingest = {
      metadata.labels = labels // {component = "ingest";};
      spec = {
        schedule = "0 */4 * * *";  # Every 4 hours
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 2;
        jobTemplate.spec.template = {
          metadata.labels = labels // {component = "ingest";};
          spec = {
            affinity = nexusPreferredAffinity;
            restartPolicy = "OnFailure";
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1000;
              runAsGroup = 1000;
              fsGroup = 1000;
            };
            containers = {
              _namedlist = true;
              ingest = {
                image = "docker.io/library/python:3.13-alpine";
                command = ["python3" "/scripts/ingest.py"];
                securityContext = {
                  runAsNonRoot = true;
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = ["ALL"];
                  seccompProfile.type = "RuntimeDefault";
                };
                env = {
                  _namedlist = true;
                  VALKEY_HOST = {name = "VALKEY_HOST"; value = "valkey.search.svc.cluster.local";};
                  VALKEY_PORT = {name = "VALKEY_PORT"; value = "6379";};
                  VALKEY_DB = {name = "VALKEY_DB"; value = "0";};
                  QDRANT_URL = {name = "QDRANT_URL"; value = "http://qdrant.ai-inference.svc.cluster.local:6333";};
                  QDRANT_COLLECTION = {name = "QDRANT_COLLECTION"; value = "searxng-results";};
                  GATEWAY_URL = {name = "GATEWAY_URL"; value = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080";};
                  EMBEDDING_MODEL = {name = "EMBEDDING_MODEL"; value = "BidirLM/BidirLM-Omni-2.5B-Embedding";};
                  EMBEDDING_DIM = {name = "EMBEDDING_DIM"; value = "2048";};
                  QUALITY_THRESHOLD = {name = "QUALITY_THRESHOLD"; value = "0.6";};
                  BATCH_SIZE = {name = "BATCH_SIZE"; value = "10";};
                  FETCH_TIMEOUT = {name = "FETCH_TIMEOUT"; value = "15";};
                };
                resources = {
                  requests = {cpu = "100m"; memory = "128Mi";};
                  limits = {cpu = "500m"; memory = "512Mi";};
                };
                volumeMounts = {
                  _namedlist = true;
                  scripts = {mountPath = "/scripts";};
                  tmp = {mountPath = "/tmp";};
                };
              };
            };
            volumes = {
              _namedlist = true;
              scripts.configMap = {
                name = "searxng-ingest-script";
                defaultMode = 493;  # 0755
              };
              tmp.emptyDir = {};
            };
          };
        };
      };
    };

    # ── CronJob: weekly stale document re-indexing ───────────────
    search.CronJob.searxng-stale-reindex = {
      metadata.labels = labels // {component = "stale-reindex";};
      spec = {
        schedule = "0 3 * * 0";  # Sunday at 03:00
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 2;
        jobTemplate.spec.template = {
          metadata.labels = labels // {component = "stale-reindex";};
          spec = {
            affinity = nexusPreferredAffinity;
            restartPolicy = "OnFailure";
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1000;
              runAsGroup = 1000;
              fsGroup = 1000;
            };
            containers = {
              _namedlist = true;
              reindex = {
                image = "docker.io/library/python:3.13-alpine";
                command = ["python3" "/scripts/reindex.py"];
                securityContext = {
                  runAsNonRoot = true;
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = ["ALL"];
                  seccompProfile.type = "RuntimeDefault";
                };
                env = {
                  _namedlist = true;
                  QDRANT_URL = {name = "QDRANT_URL"; value = "http://qdrant.ai-inference.svc.cluster.local:6333";};
                  QDRANT_COLLECTION = {name = "QDRANT_COLLECTION"; value = "searxng-results";};
                  GATEWAY_URL = {name = "GATEWAY_URL"; value = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080";};
                  EMBEDDING_MODEL = {name = "EMBEDDING_MODEL"; value = "BidirLM/BidirLM-Omni-2.5B-Embedding";};
                  STALE_DAYS = {name = "STALE_DAYS"; value = "30";};
                  BATCH_SIZE = {name = "BATCH_SIZE"; value = "20";};
                };
                resources = {
                  requests = {cpu = "100m"; memory = "128Mi";};
                  limits = {cpu = "500m"; memory = "512Mi";};
                };
                volumeMounts = {
                  _namedlist = true;
                  scripts = {mountPath = "/scripts";};
                  tmp = {mountPath = "/tmp";};
                };
              };
            };
            volumes = {
              _namedlist = true;
              scripts.configMap = {
                name = "searxng-stale-reindex-script";
                defaultMode = 493;  # 0755
              };
              tmp.emptyDir = {};
            };
          };
        };
      };
    };

    # ── NetworkPolicy: allow ingest pod egress to Qdrant + Gateway ─
    search.NetworkPolicy.allow-ingest-egress = {
      metadata.labels = labels // {policy = "allow-ingest-egress";};
      spec = {
        podSelector.matchLabels.app = "searxng-ingest";
        policyTypes = ["Egress"];
        egress = [
          # DNS
          {
            to = [{namespaceSelector.matchLabels.name = "kube-system";}];
            ports = [
              {protocol = "UDP"; port = 53;}
              {protocol = "TCP"; port = 53;}
            ];
          }
          # Qdrant (ai-inference namespace)
          {
            to = [{
              namespaceSelector.matchLabels.name = "ai-inference";
              podSelector.matchLabels.app = "qdrant";
            }];
            ports = [{protocol = "TCP"; port = 6333;}];
          }
          # AI Inference Gateway (ai-inference namespace)
          {
            to = [{
              namespaceSelector.matchLabels.name = "ai-inference";
              podSelector.matchLabels.app = "ai-inference-gateway";
            }];
            ports = [{protocol = "TCP"; port = 8080;}];
          }
          # Valkey (same namespace)
          {
            to = [{podSelector.matchLabels.app = "valkey";}];
            ports = [{protocol = "TCP"; port = 6379;}];
          }
          # External HTTP/HTTPS for content fetching
          {
            to = [{ipBlock.cidr = "0.0.0.0/0";}];
            ports = [
              {protocol = "TCP"; port = 80;}
              {protocol = "TCP"; port = 443;}
            ];
          }
        ];
      };
    };

    # ── NetworkPolicy: allow ingest pod ingress (for health checks) ─
    search.NetworkPolicy.allow-ingest-ingress = {
      metadata.labels = labels // {policy = "allow-ingest-ingress";};
      spec = {
        podSelector.matchLabels.app = "searxng-ingest";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{ipBlock.cidr = cluster.subnet;}];
            ports = [{protocol = "TCP"; port = 8080;}];
          }
        ];
      };
    };
  };
}
