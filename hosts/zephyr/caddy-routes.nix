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

  # Protected routes — Caddy forward_auth + oauth2-proxy (Casdoor SSO).
  # forward_auth automatically sets X-Forwarded-Host/Proto/Uri on the auth request.
  # copy_headers copies user identity headers from oauth2-proxy's 2xx response
  # to the backend request, enabling downstream apps to trust upstream identity.
  mkAuthRoute = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip

      forward_auth oauth2-proxy.auth.svc.cluster.local:4180 {
        uri /oauth2/auth
        copy_headers X-Forwarded-User X-Forwarded-Email X-Forwarded-Preferred-Username
      }

      reverse_proxy ${backend} {
        ${proxyHeader}
      }
    }
  '';
in
  # HTTP → HTTPS redirect for all .lan domains
  # Caddy skips auto-redirect when using manual TLS
  ":80 {
  redir https://{host}{uri} permanent
}

"
  + "\n"
  +
  # === PUBLIC SERVICES (no auth) ===
  # SSO provider itself (hostNetwork on zephyr)
  # auth.lan — Casdoor SSO UI + oauth2-proxy callback.
  # MUST handle /oauth2/* so callbacks reach oauth2-proxy (redirect_uri=https://auth.lan/oauth2/callback).
  "auth.lan {
      ${tls}
      encode zstd gzip

      # OAuth2 callback — proxy to oauth2-proxy (NOT Casdoor)
      handle /oauth2/* {
        reverse_proxy oauth2-proxy.auth.svc.cluster.local:4180
      }

      handle {
        reverse_proxy casdoor.auth.svc.cluster.local:8000 {
          ${proxyHeader}
        }
      }
    }"
  + "\n"
  +
  # Vaultwarden via K8s service discovery (port 80) — has own auth
  mkRoute "vaultwarden.lan" "http://vaultwarden.vaultwarden.svc.cluster.local:80"
  + "\n"
  +
  # n8n automation — has own auth
  mkRoute "n8n.lan" "http://n8n.automation.svc.cluster.local:5678"
  + "\n"
  +
  # Search (SearXNG via K8s service discovery) — public search tool
  mkRoute "searxng.lan, search.lan" "http://searxng.search.svc.cluster.local:8080"
  + "\n"
  +
  # === PROTECTED SERVICES (central SSO) ===
  # Haven via K8s service discovery (HTTPS backend, skip verification)
  "haven.lan {
      ${tls}
      encode zstd gzip

      forward_auth oauth2-proxy.auth.svc.cluster.local:4180 {
        uri /oauth2/auth
        copy_headers X-Forwarded-User X-Forwarded-Email X-Forwarded-Preferred-Username
      }

      reverse_proxy https://haven.haven.svc.cluster.local:3000 {
        ${proxyHeader}
        transport http {
          tls
          tls_insecure_skip_verify
        }
      }
    }"
  + "\n"
  +
  # AI Inference Gateway — OpenAI-compatible API
  mkAuthRoute "ai-inference.lan" "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080"
  + "\n"
  +
  # Brain / Knowledge Fabric API
  mkAuthRoute "brain.lan" "http://knowledge-fabric-api.ai-inference.svc.cluster.local:3000"
  + "\n"
  +
  # Qdrant vector database
  mkAuthRoute "qdrant.lan" "http://qdrant.ai-inference.svc.cluster.local:6333"
  + "\n"
  +
  # Mission Control via K8s service discovery
  mkAuthRoute "mission-control.lan" "http://mission-control.orchestration.svc.cluster.local:3000"
  + "\n"
  +
  # Kagent UI via K8s service discovery
  mkAuthRoute "kagent.lan" "http://kagent-controller.kagent.svc.cluster.local:8083"
  + "\n"
  +
  # Grafana via K8s service discovery
  mkAuthRoute "grafana.lan" "http://grafana.monitoring.svc.cluster.local:3000"
  + "\n"
  +
  # Open WebUI via K8s service discovery
  mkAuthRoute "openwebui.lan" "http://open-webui.ai-inference.svc.cluster.local:8080"
  + "\n"
  +
  # Hermes Workspace (zephyr, port 3002)
  mkAuthRoute "workspace.lan" "http://127.0.0.1:3002"
  + "\n"
  + ""
