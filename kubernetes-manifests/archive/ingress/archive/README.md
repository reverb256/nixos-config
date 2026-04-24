# Caddy Ingress Controller

Caddy DaemonSet providing ingress for all cluster services, fronted by the zephyr edge proxy via VIP 10.1.1.100.

**Full architecture doc:** `docs/kubernetes/caddy-ingress-architecture.md`

## Quick Start

```bash
# Apply all manifests
kubectl apply -f /etc/nixos/kubernetes-manifests/ingress/

# Verify deployment
kubectl -n ingress-system get pods -o wide
kubectl -n ingress-system get svc

# Check logs
kubectl -n ingress-system logs -l app.kubernetes.io/name=caddy-ingress
```

## Services

| Hostname | Backend | Status |
|----------|---------|--------|
| `openwebui.cluster.local` / `openwebui.lan` | `open-webui.ai-inference:8080` | ✅ Active |
| `llama.cluster.local` / `llama.lan` | `llama-server.ai-inference:8080` | ⏳ Route ready |
| `mining.cluster.local` / `mining.lan` | `xmrig-proxy.mining:8081` | ⏳ Route ready |

## Access Methods

| Method | URL | Notes |
|--------|-----|-------|
| VIP HTTPS | `https://openwebui.cluster.local/` | Primary, TLS via zephyr |
| VIP HTTPS (.lan) | `https://openwebui.lan/` | Alternative domain |
| HTTP NodePort | `http://<node>:30080/` | Direct, no TLS |
| HTTPS NodePort | `https://<node>:30443/` | Direct, TLS internal |

Nodes with Caddy: nexus (10.1.1.120), forge (10.1.1.130), sentry (10.1.1.140).

## Adding a New Route

1. Edit `02-configmap.yaml` — add HTTPS and HTTP route blocks
2. Edit `hosts/zephyr/configuration.nix` — add edge proxy route + DNS entries
3. Patch CoreDNS NodeHosts with new hostname → VIP
4. Apply:
   ```bash
   kubectl apply -f 02-configmap.yaml
   kubectl rollout restart daemonset -n ingress-system caddy-ingress
   just switch
   ```

See `docs/kubernetes/caddy-ingress-architecture.md` for the complete guide.

## TLS

- **Issuer:** Caddy Local Authority (ECC, self-signed)
- **Method:** `tls internal` on all site blocks
- **Default SNI:** `cluster.local` (for IP-only clients)
- **Trust:** CA cert installed on zephyr via `security.caddyCa.enable`

## Monitoring

```bash
# Caddy admin API (metrics + config)
kubectl -n ingress-system port-forward svc/caddy-admin 2019:2019
curl http://localhost:2019/config/
```

## Files

| File | Purpose |
|------|---------|
| `00-namespace.yaml` | `ingress-system` namespace |
| `01-serviceaccount.yaml` | RBAC service account |
| `02-configmap.yaml` | Caddyfile (service routes) |
| `03-daemonset.yaml` | Caddy DaemonSet (nexus/forge/sentry) |
| `04-service.yaml` | NodePort service (30080/30443) |
| `04-prometheus-alerts.yaml` | Alerting rules |
| `06-prometheus-servicemonitor.yaml` | Prometheus scrape config |
| `07-networkpolicy.yaml` | Network policy |
| `08-metrics-service.yaml` | Metrics ClusterIP service |
