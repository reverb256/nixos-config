# Caddy Routing Reference — Working Examples

Complete working examples from the cluster. Use these as copy-paste templates.

## Zephyr Caddy Routes

Source: `hosts/zephyr/caddy-routes.nix`

Zephyr uses helper functions `mkRoute` and `mkAuthRoute` that encode TLS, compression, and auth patterns.

### Helper Definitions

```nix
{cluster}: let
  tls = "tls /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key";
  proxyHeader = ''
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Host {host}
    header_up X-Forwarded-Proto {scheme}
  '';

  # Public routes — no auth required
  mkRoute = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip
      reverse_proxy ${backend} {
        ${proxyHeader}
      }
    }
  '';

  # Protected routes — Caddy forward_auth + oauth2-proxy (Casdoor SSO)
  mkAuthRoute = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip

      # OAuth2 callback — always proxy to oauth2-proxy
      handle /oauth2/* {
        reverse_proxy localhost:4180 {
          header_up X-Real-IP {remote_host}
          header_up X-Forwarded-Uri {uri}
        }
      }

      # Everything else — auth check, then backend on success
      handle {
        forward_auth localhost:4180 {
          uri /oauth2/auth
          copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username X-Auth-Request-Access-Token
        }

        reverse_proxy ${backend}
      }
    }
  '';
in
  # Public services:
  mkRoute "myapp.lan" "http://127.0.0.1:8080" +
  # Protected services:
  mkAuthRoute "admin.lan" "http://127.0.0.1:9090" +
  ""
```

### Route Registration Pattern

1. **Public service**: `mkRoute "domain.lan" "http://host:port"`
2. **Protected service**: `mkAuthRoute "domain.lan" "http://host:port"`
3. **Multi-domain**: `mkRoute "search.lan, searxng.lan" "http://backend"`
4. **Always end** the chain with `+ ""` (empty string terminates the concatenation)

### Backend Address Patterns

| Service Location | Address Pattern |
|-----------------|----------------|
| Local systemd service | `http://127.0.0.1:PORT` |
| K8s NodePort on same host | `http://127.0.0.1:NODEPORT` |
| K8s NodePort on different host | `http://HOST_IP:NODEPORT` |
| K8s ClusterIP (from host) | `http://CLUSTERIP:PORT` |

### DNS Registration

After adding a route, add DNS in `modules/network/cluster-dns.nix`:

```nix
# In the unbound local-zone section:
"myapp.lan. IN A 10.1.1.100"  # VIP address
```

## Nexus Caddy Routes

Source: `modules/services/cluster-services.nix`

Nexus uses a service registry pattern where each service declares its domain, backend, and protection status.

### Service Registry Entry

```nix
my-app = {
  domain = "myapp.lan";
  backend = "http://127.0.0.1:8080";
  protected = true;    # true = SSO-protected, false = public
  compress = true;     # Optional, default true
};
```

### How It Works

1. `services.cluster-services.registry` attrset defines all services
2. `buildCaddyBlock` generates Caddy config from registry
3. `buildCaddyfile` assembles the complete Caddyfile
4. `mkPublicBlock` generates public route config
5. `mkProtectedBlock` generates SSO-protected route config

### Adding a New Service on Nexus

1. Add entry to the registry in `cluster-services.nix`
2. Add DNS in `cluster-dns.nix`
3. Deploy: `just deploy nexus`

## Architecture Diagram

```
Browser → .lan domain → VIP 10.1.1.100 (keepalived)
  → Caddy (zephyr or nexus)
    → forward_auth localhost:4180 (oauth2-proxy)
      → auth.lan (Casdoor OIDC)
    → reverse_proxy backend
```

## Service Classification

| Type | Services | Pattern |
|------|----------|---------|
| Public | searxng.lan, ai-inference.lan | `mkRoute` |
| Protected (SSO) | haven.lan, openwebui.lan, grafana.lan, mission-control.lan | `mkAuthRoute` |
| Auth provider | auth.lan | `mkRoute` (special — must be public) |
