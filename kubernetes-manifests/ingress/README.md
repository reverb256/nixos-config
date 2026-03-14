# Caddy Ingress Controller

This directory contains the manifests for deploying Caddy as the Kubernetes Ingress Controller for the cluster.

## Quick Start

```bash
# Apply all manifests
kubectl apply -f /etc/nixos/kubernetes-manifests/ingress/

# Verify deployment
kubectl -n ingress-system get pods
kubectl -n ingress-system get svc

# Check logs
kubectl -n ingress-system logs -l app.kubernetes.io/name=caddy-ingress
```

## Architecture

```
External Traffic (NodePort 30080/30443)
          ↓
    Caddy DaemonSet (on each node)
          ↓
    Service Discovery (Kubernetes DNS)
          ↓
    Backend Services (ai-inference, searxng, etc.)
```

## Services Configured

| Service | Internal URL | External URL | Backend |
|---------|-------------|--------------|---------|
| AI Inference | `ai.cluster.local` | `ai.zephyr.tigris-ule.ts.net:9002` | `ai-inference:8080` |
| SearXNG | `search.cluster.local` | `search.zephyr.tigris-ule.ts.net:9001` | `searxng:7777` |
| Vaultwarden | N/A | `vaultwarden.zephyr.tigris-ule.ts.net` | `vaultwarden:80` |
| GlitchTip | N/A | `glitchip.zephyr.tigris-ule.ts.net` | `glitchtip-web:8000` |
| Akash Provider | `provider.cluster.local` | TBD | `akash-provider:8443` |

## Access Methods

### Internal (Cluster)
```bash
# From any pod in the cluster
curl http://ai.cluster.local
curl http://search.cluster.local
```

### External (NodePort)
```bash
# Via any node IP
curl http://10.1.1.110:30080  # HTTP
curl https://10.1.1.110:30443 # HTTPS
```

### External (Tailscale)
```bash
# Via Tailscale MagicDNS
curl https://ai.zephyr.tigris-ule.ts.net:9002
curl https://search.zephyr.tigris-ule.ts.net:9001
```

## Configuration

### Adding a New Route

Edit `02-configmap.yaml` and add your route:

```caddy
your-service.cluster.local {
    reverse_proxy your-service.namespace.svc.cluster.local:8080
}
```

Then apply:
```bash
kubectl apply -f 02-configmap.yaml
kubectl -n ingress-system rollout restart daemonset/caddy-ingress
```

### TLS Certificates

**Internal Services** (.cluster.local):
- Uses `tls internal` - Caddy's internal CA
- No external certificate needed
- Works within the cluster and Tailscale VPN

**Public Services**:
```caddy
# Enable automatic Let's Encrypt
your-domain.com {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
    reverse_proxy backend:8080
}
```

## Monitoring

### Metrics
Caddy exposes Prometheus metrics on the admin endpoint (port 2019):

```bash
# Port-forward to access metrics
kubectl -n ingress-system port-forward svc/caddy-admin 2019:2019
curl http://localhost:2019/metrics
```

### Health Check
```bash
kubectl -n ingress-system exec -l app.kubernetes.io/name=caddy-ingress -- \
    curl http://localhost:2019/health
```

## Troubleshooting

### Check pod status
```bash
kubectl -n ingress-system get pods -o wide
kubectl -n ingress-system describe pod <pod-name>
```

### View logs
```bash
# All pods
kubectl -n ingress-system logs -l app.kubernetes.io/name=caddy-ingress

# Specific pod
kubectl -n ingress-system logs <pod-name> -f
```

### Test configuration
```bash
# Port-forward to test locally
kubectl -n ingress-system port-forward svc/caddy-ingress-internal 8080:80
curl http://localhost:8080
```

### Check Caddy admin API
```bash
kubectl -n ingress-system exec -l app.kubernetes.io/name=caddy-ingress -- \
    curl http://localhost:2019/config/
```

## Upgrading

```bash
# Update the image
kubectl -n ingress-system set image daemonset/caddy-ingress \
    caddy=caddy:2.9-alpine

# Or edit the DaemonSet
kubectl -n ingress-system edit daemonset caddy-ingress
```

## Migration from systemd Caddy

The old Caddy configuration in `hosts/zephyr/configuration.nix` can be removed once all services are migrated to Kubernetes:

```nix
# Remove this from zephyr/configuration.nix
# services.caddy = {
#   enable = true;
#   configFile = pkgs.writeText "Caddyfile" ''...'' ;
# };
```

## Next Steps

1. ✅ Deploy Caddy Ingress Controller
2. ⏳ Create Kubernetes Services for each application
3. ⏳ Update DNS records (if using public domains)
4. ⏳ Remove systemd Caddy from NixOS config
5. ⏳ Set up monitoring dashboards (Grafana)

## References

- [Caddy Documentation](https://caddyserver.com/docs/)
- [Caddy Kubernetes Ingress](https://github.com/caddyserver/ingress)
- [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
