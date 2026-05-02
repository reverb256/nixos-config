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

  # Protected routes — uses the expanded forward_auth form from Caddy docs.
  # Key: reverse_proxy with handle_response that only passes on 2xx.
  # Non-2xx auth responses are returned to client and execution stops.
  mkAuthRoute = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip

      # OAuth2 callback endpoint — always proxy to auth service
      handle /oauth2/* {
        reverse_proxy localhost:4180
      }

      # Everything else — auth check, then backend on success
      handle {
        reverse_proxy localhost:4180 {
          method GET
          rewrite /oauth2/auth

          header_up X-Forwarded-Host {host}
          header_up X-Forwarded-Method {method}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Uri {uri}

          # On successful auth (2xx), copy auth headers and continue
          @good status 2xx
          handle_response @good {
            request_header X-Auth-Request-User {rp.header.X-Auth-Request-User}
            request_header X-Auth-Request-Email {rp.header.X-Auth-Request-Email}
            request_header X-Auth-Request-Preferred-Username {rp.header.X-Auth-Request-Preferred-Username}
            request_header X-Auth-Request-Access-Token {rp.header.X-Auth-Request-Access-Token}

            reverse_proxy ${backend} {
              ${proxyHeader}
            }
          }

          # On auth failure (401), redirect to login
          @unauth status 401
          handle_response @unauth {
            redir /oauth2/start?rd={scheme}://{host}{uri} 302
          }
        }
      }
    }
  '';
in
  # === PUBLIC SERVICES (no auth) ===
  # ai.lan -> llama-server-3090 (host port 1237)
  mkRoute "ai.lan" "http://127.0.0.1:1237" +
  # ai-inference.lan -> AI Gateway (NodePort 30880)
  mkRoute "ai-inference.lan" "http://10.15.67.242:8080" +
  # brain.lan -> Knowledge Fabric API (via Flannel pod IP)
  mkRoute "brain.lan" "http://10.244.1.7:3000" +
  # Search (SearXNG NodePort 32081)
  mkRoute "searxng.lan, search.lan" "http://127.0.0.1:32081" +
  # SSO provider itself
  mkRoute "auth.lan" "127.0.0.1:8000" +

  # === PROTECTED SERVICES (central SSO) ===
  # Haven (NodePort 32100)
  mkAuthRoute "haven.lan" "http://127.0.0.1:32100" +
  # Mission Control (NodePort 32101)
  mkAuthRoute "mission-control.lan" "http://127.0.0.1:32101" +
  # Kagent UI (NodePort 32103)
  mkAuthRoute "kagent.lan" "http://127.0.0.1:32103" +
  # Grafana (NodePort 32102)
  mkAuthRoute "grafana.lan" "http://127.0.0.1:32102" +
  # Open WebUI (NodePort 32080)
  mkAuthRoute "openwebui.lan" "http://127.0.0.1:32080" +
  # Llama Zephyr (host port 1237)
  mkAuthRoute "llama.zephyr.lan" "http://127.0.0.1:1237" +
  # Llama Sentry (Sentry host IP)
  mkAuthRoute "llama.sentry.lan" "http://10.1.1.140:1235" +
  ""
