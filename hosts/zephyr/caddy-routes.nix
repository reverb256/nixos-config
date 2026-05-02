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
  # Pattern from official oauth2-proxy/Caddy integration docs.
  # forward_auth sends GET /oauth2/auth to oauth2-proxy:
  #   - 2xx: copies auth headers, continues to reverse_proxy
  #   - 401: copies response (401) to client → browser sees redirect
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
  # Vaultwarden (nexus NodePort 32110)
  mkRoute "vaultwarden.lan" "http://10.1.1.120:32110" +
  ""
