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

  # Protected routes — Caddy reverse_proxy + oauth2-proxy (Casdoor SSO).
  # Uses reverse_proxy to oauth2-proxy for auth check:
  #   - 2xx: proxy to backend, forwarding user identity from oauth2-proxy
  #         response headers via {rp.header.*} placeholders (Caddy 2.8+)
  #   - 401: redirect to auth.lan login (same-origin for CSRF)
  mkAuthRoute = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip

      reverse_proxy oauth2-proxy.auth.svc.cluster.local:4180 {
        method GET
        rewrite /oauth2/auth

        # Auth successful (2xx) — proxy to backend with user identity
        @auth_ok status 2xx
        handle_response @auth_ok {
          reverse_proxy ${backend} {
            ${proxyHeader}
            header_up X-Auth-Request-User {rp.header.X-Auth-Request-User}
            header_up X-Auth-Request-Email {rp.header.X-Auth-Request-Email}
            header_up X-Auth-Request-Preferred-Username {rp.header.X-Auth-Request-Preferred-Username}
            # Override XFF/X-Real-IP to Caddy IP (MC does exact string match, not CIDR)
            header_up X-Forwarded-For 10.1.1.110
            header_up X-Real-IP 10.1.1.110
          }
        }

        # Auth failed (401) — redirect to login on auth.lan
        @unauth status 401
        handle_response @unauth {
          redir https://auth.lan/oauth2/start?rd={scheme}://{host}{uri} 302
        }
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

      reverse_proxy oauth2-proxy.auth.svc.cluster.local:4180 {
        method GET
        rewrite /oauth2/auth

        @auth_ok status 2xx
        handle_response @auth_ok {
          reverse_proxy https://haven.haven.svc.cluster.local:3000 {
            ${proxyHeader}
            header_up X-Auth-Request-User {rp.header.X-Auth-Request-User}
            header_up X-Auth-Request-Email {rp.header.X-Auth-Request-Email}
            header_up X-Auth-Request-Preferred-Username {rp.header.X-Auth-Request-Preferred-Username}
            # Override XFF/X-Real-IP to Caddy IP (MC does exact string match, not CIDR)
            header_up X-Forwarded-For 10.1.1.110
            header_up X-Real-IP 10.1.1.110
            transport http {
              tls
              tls_insecure_skip_verify
            }
          }
        }

        @unauth status 401
        handle_response @unauth {
          redir https://auth.lan/oauth2/start?rd={scheme}://{host}{uri} 302
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
