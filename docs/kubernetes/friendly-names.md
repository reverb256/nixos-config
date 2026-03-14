# Friendly Service Names - Quick Reference

**Status:** ✅ Configured | **Updated:** 2026-03-14

---

## How It Works

```
You type:              http://ai.cluster.local
                         ↓
Unbound DNS resolves → Caddy Ingress (10.1.1.120:30443)
                         ↓
Caddy routes to →     ai-inference.default.svc.cluster.local:8080
                         ↓
Service responds
```

---

## Available Friendly Names

| Friendly URL | Service | Purpose |
|--------------|---------|---------|
| `ai.cluster.local` | ai-inference | AI/LLM API gateway |
| `llm.cluster.local` | ai-inference | LM Studio backend |
| `rag.cluster.local` | ai-inference | RAG vector search |
| `home.cluster.local` | home-assistant | Smart home hub |
| `vault.cluster.local` | vaultwarden | Password manager |
| `files.cluster.local` | nextcloud | File storage |
| `search.cluster.local` | searxng | Privacy search |
| `errors.cluster.local` | glitchtip | Error tracking |
| `git.cluster.local` | gitea | Code hosting |
| `ci.cluster.local` | garnix | CI/CD |
| `metrics.cluster.local` | prometheus | Metrics |
| `dash.cluster.local` | grafana | Dashboards |
| `gpu.cluster.local` | akash-provider | GPU compute |

**Pattern:** `<name>.cluster.local` → Kubernetes service

### Node Dashboards (.lan)

| Friendly URL | Node | Purpose |
|--------------|------|---------|
| `zephyr.lan` | Zephyr | Control plane, workstation dashboard |
| `nexus.lan` | Nexus | Storage, build server dashboard |
| `forge.lan` | Forge | Multi-GPU, mining dashboard |
| `sentry.lan` | Sentry | Monitoring dashboard |

**Pattern:** `<node>.lan` → Node-specific dashboard (static content served via nginx)

---

## Adding New Friendly Names

### Option 1: Use the Helper Script

```bash
./add-friendly-route.sh <name> <backend-service> [namespace] [port]

# Examples:
./add-friendly-route.sh chat n8n default 5678
./add-friendly-route.sh registry gitea infrastructure 5000
./add-friendly-route.sh monitor prometheus monitoring 9090
```

### Option 2: Edit Caddyfile Directly

Edit `/etc/nixos/kubernetes-manifests/ingress/02-configmap.yaml`:

```nix
# Add your route in the Caddyfile section
your-service.cluster.local {
  reverse_proxy your-backend.namespace.svc.cluster.local:8080 {
    header_up Host {host}
    header_up X-Real-IP {remote_host}
  }
}
```

Then apply:
```bash
kubectl apply -f 02-configmap.yaml
kubectl -n ingress-system rollout restart daemonset/caddy-ingress
```

---

## Access Methods

| Method | URL | Example |
|--------|-----|---------|
| **Browser** | `http://<name>.cluster.local` | http://ai.cluster.local |
| **CLI** | `curl http://<name>.cluster.local` | `curl http://metrics.cluster.local/api/v1/query` |
| **Internal** | `http://<name>.cluster.local` from any cluster host | Works everywhere |
| **External** | `http://10.1.1.120:30080` with Host header | Via NodePort |

---

## Naming Conventions

### Categories

| Category | Pattern | Examples |
|----------|--------|----------|
| **AI/ML** | `ai`, `llm`, `rag` | `ai.cluster.local` |
| **Home Lab** | `home`, `vault`, `media` | `home.cluster.local` |
| **Dev Tools** | `git`, `ci`, `db` | `git.cluster.local` |
| **Monitoring** | `metrics`, `logs`, `dash` | `dash.cluster.local` |
| **Utilities** | `search`, `chat`, `files` | `search.cluster.local` |

### Short Aliases

Create memorable shortcuts:
- `dash` → Grafana (instead of grafana.cluster.local)
- `logs` → Loki (when deployed)
- `chat` → n8n automation
- `code` → Gitea

---

## Host-Specific Services

For systemd services on specific hosts, include the hostname:

| Service Type | Pattern | Example |
|--------------|--------|---------|
| **Zephyr desktop** | `<service>.zephyr.cluster.local` | `stream.zephyr.cluster.local` |
| **Nexus storage** | `<service>.nexus.cluster.local` | `storage.nexus.cluster.local` |
| **Sentry monitoring** | `<service>.sentry.cluster.local` | `monitor.sentry.cluster.local` |

These route directly to systemd services (bypassing K8s).

---

## Migration from systemd Service Gateway

The old Service Gateway pattern provided URLs like `ai.zephyr`. To migrate:

1. **Update clients** to use `ai.cluster.local`
2. **Add Caddy route** pointing to K8s service
3. **Deploy service to K8s** (when ready)
4. **Remove old systemd Caddy config**

| Old (systemd) | New (K8s) |
|---------------|-----------|
| `ai.zephyr:8080` | `ai.cluster.local` |
| `search.zephyr:7777` | `search.cluster.local` |
| `cloud.zephyr:8080` | `files.cluster.local` |

---

## Testing Your Routes

```bash
# Test from anywhere in cluster
curl http://ai.cluster.local
curl http://home.cluster.local/api/services

# Test with specific Host header
curl -H "Host: ai.cluster.local" http://10.1.1.120:30080/

# Test HTTPS (with internal CA)
curl -k https://ai.cluster.local

# Check DNS resolution
nslookup ai.cluster.local
dig ai.cluster.local

# Check Caddy config
kubectl -n ingress-system exec -l app.kubernetes.io/name=caddy-ingress -- \
  curl -s http://localhost:2019/config/
```

---

## Troubleshooting

### "Name does not resolve"

1. Check Unbound is running: `systemctl status unbound`
2. Check local-data includes your name: `grep "your-service" /etc/nixos/modules/services/unbound-cluster.nix`
3. Test DNS: `nslookup your-service.cluster.local`

### "502 Bad Gateway"

1. Backend service not running: `kubectl get svc -A | grep backend-name`
2. Wrong port: Check service definition
3. Wrong namespace: Check `namespace.svc.cluster.local`

### "Connection refused"

1. Caddy pods not ready: `kubectl -n ingress-system get pods`
2. NodePort blocked: Check firewall allows 30080/30443

---

## See Also

- **Caddy Ingress Documentation:** `/etc/nixos/docs/kubernetes/caddy-ingress.md`
- **Ingress README:** `/etc/nixos/kubernetes-manifests/ingress/README.md`
- **Unbound Config:** `/etc/nixos/modules/services/unbound-cluster.nix`
- **Network Constants:** `/etc/nixos/modules/network-constants.nix`

---

**Last Updated:** 2026-03-14 | **Maintainer:** j_kro
