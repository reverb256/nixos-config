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
  # Uses forward_auth which natively copies X-Auth-Request-* response headers
  # to the backend request. 401 → redirect to auth.lan login.
  mkAuthRoute = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip

      # forward_auth natively copies X-Auth-Request-* response headers
      # to the backend request (unlike handle_response + reverse_proxy
      # where {rp.header.*} is NOT available in the inner proxy context).
      forward_auth oauth2-proxy.auth.svc.cluster.local:4180 {
        uri /oauth2/auth
        copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username
      }

      # forward_auth returns 401 to client — handle_errors catches it
      handle_errors 4xx {
        @is401 {
          expression {http.error.status_code} == 401
        }
        redir @is401 https://auth.lan/oauth2/start?rd={scheme}://{host}{uri} 302
      }

      reverse_proxy ${backend} {
        ${proxyHeader}
        # Override XFF/X-Real-IP to Caddy IP (MC does exact string match, not CIDR)
        header_up X-Forwarded-For 10.1.1.110
        header_up X-Real-IP 10.1.1.110
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
        copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username
      }

      @notAuth status 401
      handle_response @notAuth {
        redir https://auth.lan/oauth2/start?rd={scheme}://{host}{uri} 302
      }

      reverse_proxy https://haven.haven.svc.cluster.local:3000 {
        ${proxyHeader}
        header_up X-Forwarded-For 10.1.1.110
        header_up X-Real-IP 10.1.1.110
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
