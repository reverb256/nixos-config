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
  # Use manual reverse_proxy pattern to handle 401 responses with redirect
  mkAuthRoute = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip

      # OAuth2 callback — always proxy to oauth2-proxy
      handle /oauth2/* {
        reverse_proxy oauth2-proxy.auth.svc.cluster.local:4180
      }

      # Everything else — auth check with backend proxy
      reverse_proxy oauth2-proxy.auth.svc.cluster.local:4180 {
        method GET
        rewrite /oauth2/auth
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Uri {uri}

        # Auth successful (2xx) - proxy to actual backend
        @auth_ok status 2xx
        handle_response @auth_ok {
          reverse_proxy ${backend}
        }

        # Auth failed (401) - redirect to login
        @unauth status 401
        handle_response @unauth {
          redir https://auth.lan/oauth2/start?rd={scheme}://{host}{uri} 302
        }
      }
    }
  '';
in
  # === PUBLIC SERVICES (no auth) ===
  # ai.lan -> llama-server-3090 (hostNetwork on zephyr, host port 1237)
  mkRoute "ai.lan" "http://127.0.0.1:1237" + "\n" +
  # ai-inference.lan -> AI Gateway via K8s service discovery
  mkRoute "ai-inference.lan" "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080" + "\n" +
  # brain.lan -> Knowledge Fabric API via K8s service discovery
  mkRoute "brain.lan" "http://knowledge-fabric-api.ai-inference.svc.cluster.local:3000" + "\n" +
  # Search (SearXNG via K8s service discovery - automatic pod routing)
  mkRoute "searxng.lan, search.lan" "http://searxng.search.svc.cluster.local:8080" + "\n" +
  # SSO provider itself (hostNetwork on zephyr)
  # auth.lan — Casdoor SSO UI + oauth2-proxy callback.
  # MUST handle /oauth2/* so callbacks reach oauth2-proxy (redirect_uri=https://auth.lan/oauth2/callback).
  ("auth.lan {
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
    }") + "\n" +
  # Vaultwarden via K8s service discovery (port 80)
  mkRoute "vaultwarden.lan" "http://vaultwarden.vaultwarden.svc.cluster.local:80" + "\n" +

  # === PROTECTED SERVICES (central SSO) ===
  # Haven via K8s service discovery (HTTPS backend, skip verification)
  ("haven.lan {
      ${tls}
      encode zstd gzip

      handle /oauth2/* {
        reverse_proxy oauth2-proxy.auth.svc.cluster.local:4180
      }

      reverse_proxy oauth2-proxy.auth.svc.cluster.local:4180 {
        method GET
        rewrite /oauth2/auth
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Uri {uri}

        @auth_ok status 2xx
        handle_response @auth_ok {
          reverse_proxy https://haven.haven.svc.cluster.local:3000 {
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
    }") + "\n" +
  # Mission Control via K8s service discovery
  mkAuthRoute "mission-control.lan" "http://mission-control.orchestration.svc.cluster.local:3000" + "\n" +
  # Kagent UI via K8s service discovery
  mkAuthRoute "kagent.lan" "http://kagent-controller.kagent.svc.cluster.local:8083" + "\n" +
  # Grafana via K8s service discovery
  mkAuthRoute "grafana.lan" "http://grafana.monitoring.svc.cluster.local:3000" + "\n" +
  # Open WebUI via K8s service discovery
  mkAuthRoute "openwebui.lan" "http://openwebui.ai-inference.svc.cluster.local:3000" + "\n" +
  # Llama Zephyr (hostNetwork on zephyr, host port 1237)
  mkAuthRoute "llama.zephyr.lan" "http://127.0.0.1:1237" + "\n" +
  # Llama Sentry via K8s service discovery
  mkAuthRoute "llama.sentry.lan" "http://llama-server-sentry.ai-inference.svc.cluster.local:1235" + "\n" +
  ""
