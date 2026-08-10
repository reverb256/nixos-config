# Caddy Ingress Architecture

> **Status:** Reference architecture
> **Last Verified:** 2026-08-09 (checked-in configuration only)
> **Source:** `hosts/zephyr/`, `hosts/nexus/`, `modules/services/cluster-ca.nix`, `kubernetes/service-ports.nix`, and ingress manifests
>
> Verify VIP ownership, routes, certificates, NodePorts, and backend health against
> the live configuration and Kubernetes API before using this document operationally.

**Historical snapshot date:** 2026-04-05

## Overview

All cluster services are routed through a Caddy-based ingress layer with VIP failover. The architecture provides TLS termination, load balancing, and unified DNS access for all workloads.

## Architecture

```
                        ┌─────────────────────────────────────────┐
                        │            Client / Browser             │
                        └──────────────────┬──────────────────────┘
                                           │
                              DNS: *.cluster.local / *.lan
                              resolves to VIP 10.1.1.100
                                           │
                        ┌──────────────────▼──────────────────────┐
                        │     Zephyr Caddy (systemd, port 443)    │
                        │     - TLS termination (tls internal)    │
                        │     - VIP 10.1.1.100 (keepalived)       │
                        │     - Round-robin to K8s Caddy nodes    │
                        └──────────────────┬──────────────────────┘
                                           │ HTTP (port 30080)
                    ┌──────────────────────┼──────────────────────┐
                    │                      │                      │
           ┌───────▼──────┐      ┌────────▼──────┐      ┌───────▼──────┐
           │ K8s Caddy     │      │ K8s Caddy      │      │ K8s Caddy    │
           │ (nexus)       │      │ (forge)        │      │ (sentry)     │
           │ NodePort      │      │ NodePort       │      │ NodePort     │
           │ 30080/30443   │      │ 30080/30443    │      │ 30080/30443  │
           └───────┬──────┘      └────────┬──────┘      └───────┬──────┘
                   │                      │                      │
                   └──────────────────────┼──────────────────────┘
                                          │ ClusterIP routing
                    ┌─────────────────────┼─────────────────────┐
                    │                     │                     │
           ┌───────▼──────┐      ┌───────▼──────┐     ┌────────▼────┐
           │ :8080        │      │ :8080        │     │ :8081       │
           │ (forge)      │      │ (nexus)      │     │ (nexus)     │
           └──────────────┘      └──────────────┘     └─────────────┘
```

## Components

### Zephyr Caddy (Edge Proxy)

- **Type:** NixOS systemd service (`services.caddy`)
- **Role:** TLS termination, VIP front-end, round-robin load balancer
- **Listen:** `:443` (HTTPS), `:80` (HTTP)
- **Config:** `hosts/zephyr/configuration.nix`
- **TLS:** Verify the current certificate issuer and trust path in `modules/services/cluster-ca.nix` and the host Caddy configuration; this document's older `tls internal` description may be stale.
- **VIP:** 10.1.1.100 via keepalived (VRRP priority 110)

Zephyr is excluded from the K8s Caddy DaemonSet (OOM prevention). It proxies all requests to the K8s Caddy DaemonSet via HTTP NodePort (30080) on nexus/forge/sentry.

### K8s Caddy DaemonSet (Backend Proxy)

- **Type:** Kubernetes DaemonSet (`ingress-system/caddy-ingress`)
- **Role:** Service routing, HTTP/HTTPS serving within K8s
- **Nodes:** nexus, forge, sentry (excludes zephyr)
- **Ports:** NodePort 30080 (HTTP), 30443 (HTTPS)
- **Config:** `kubernetes-manifests/ingress/02-configmap.yaml`
- **Image:** `ghcr.io/reverb256/caddy-ingress:v2.8.0`

### Keepalived VIP

- **Module:** `modules/services/keepalived-vip.nix`
- **VIP:** 10.1.1.100
- **VRRP ID:** 51
- **Master:** zephyr (priority 110)
- **Failover:** Automatic if zephyr goes down

## Historical Service Snapshot

The service table below is a historical/reference snapshot. Verify routes and backend
health against current Caddy and Kubernetes configuration before relying on any status.

| Hostname | Service | Backend | Historical status |
|----------|---------|---------|--------|
| `openwebui.cluster.local` | Open WebUI | `open-webui.ai-inference:8080` | ✅ Active |
| `openwebui.lan` | Open WebUI (alt) | same | ✅ Active |
| `llama.cluster.local` | LLM API | `llama-server.ai-inference:8080` | ⏳ Route ready |
| `llama.lan` | LLM API (alt) | same | ⏳ Route ready |
| `mining.lan` | Mining Metrics (alt) | same | ⏳ Route ready |

The original design exposed paired `*.cluster.local` and `*.lan` names. Verify the
current names, ports, and access controls before publishing or testing a new route.

## DNS Resolution

| Layer | Method | Config |
|-------|--------|--------|
| **Cluster DNS** | CoreDNS NodeHosts | `kubectl edit configmap coredns -n kube-system` |
| **Zephyr local** | `/etc/hosts` | `networking.extraHosts` in `hosts/zephyr/configuration.nix` |
| **LAN DNS** | Unbound | `services.unbound.settings.server.local-data` in zephyr |

All three layers resolve service hostnames to VIP `10.1.1.100`.

## TLS Certificate Architecture

- **Issuer:** Verify against the current cluster CA and Caddy configuration before relying on this section.
- **Type:** The certificate model is source-controlled; do not assume the historical `tls internal` behavior described here is current.
- **Storage:** `/.local/share/caddy/certificates/local/` (emptyDir, regenerated on restart)
- **Scope:** One cert per hostname pair (e.g., `openwebui.cluster.local`, `openwebui.lan`)
- **Default SNI:** `cluster.local` (for IP-only clients)
- **Trust:** CA cert installed on zephyr via `security.caddyCa.enable = true`

### Adding a new service

To add a new service to the ingress:

1. **K8s Caddy ConfigMap** (`kubernetes-manifests/ingress/02-configmap.yaml`):
   ```caddyfile
   newservice.cluster.local, newservice.lan {
     tls internal
     encode zstd gzip
     reverse_proxy newservice.namespace.svc.cluster.local:port {
       transport http {
         read_timeout 300s
         write_timeout 300s
       }
     }
   }
   http://newservice.cluster.local, http://newservice.lan {
     encode zstd gzip
     reverse_proxy newservice.namespace.svc.cluster.local:port
   }
   ```

2. **Zephyr Caddy** (`hosts/zephyr/configuration.nix`):
   ```caddyfile
   newservice.cluster.local, newservice.lan {
     tls internal
     reverse_proxy http://10.1.1.120:30080 http://10.1.1.130:30080 http://10.1.1.140:30080 {
       lb_policy round_robin
       transport http { read_timeout 300s; write_timeout 300s }
     }
   }
   ```

3. **DNS entries** (3 places in `hosts/zephyr/configuration.nix`):
   - `networking.extraHosts`: `10.1.1.100 newservice.cluster.local newservice.lan`
   - `services.unbound.settings.server.local-data`: A records for both hostnames
   - CoreDNS NodeHosts: `kubectl patch configmap coredns -n kube-system ...`

4. **Apply**:
   ```bash
   kubectl apply -f kubernetes-manifests/ingress/02-configmap.yaml
   kubectl rollout restart daemonset -n ingress-system caddy-ingress
   just switch  # Apply zephyr config
   ```

## Files

| File | Purpose |
|------|---------|
| `kubernetes-manifests/ingress/02-configmap.yaml` | K8s Caddy Caddyfile (service routes) |
| `kubernetes-manifests/ingress/03-daemonset.yaml` | K8s Caddy DaemonSet |
| `kubernetes-manifests/ingress/04-service.yaml` | NodePort service (30080/30443) |
| `hosts/zephyr/configuration.nix` | Zephyr Caddy (edge proxy + VIP) |
| `modules/services/keepalived-vip.nix` | VIP failover configuration |
| `modules/services/cluster-ca.nix` | Internal CA (future use) |
| `modules/services/caddy-common.nix` | Shared Caddy config snippets |
| `modules/services/caddy-ingress-common.nix` | K8s ingress config templates |

## Troubleshooting

### TLS internal error on HTTPS

- Check `tls internal` is present in both K8s and zephyr Caddyfiles
- Check `default_sni cluster.local` is in global options
- Check catch-all `:443` block has `tls internal`
- Verify certs: `sudo ls /var/lib/caddy/.local/share/caddy/certificates/local/`

### 502 Bad Gateway

- Backend service not deployed or not healthy
- Check `kubectl get pods -A` for service status
- Check service DNS: `kubectl exec -n ingress-system <pod> -- nslookup <service>`

### DNS not resolving

- From zephyr: check `/etc/hosts` entries
- From cluster pods: check CoreDNS NodeHosts
- From LAN: check Unbound local-data in zephyr config

### Caddy pod not starting

- Check logs: `kubectl logs -n ingress-system <pod>`
- Check image pull: `kubectl describe pod -n ingress-system <pod>`
- Verify ConfigMap: `kubectl get configmap caddy-config -n ingress-system -o yaml`
