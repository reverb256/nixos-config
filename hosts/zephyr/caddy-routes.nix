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

  # Protected routes — central oauth2-proxy forward_auth
  mkAuthRoute = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip

      # Auth check against central oauth2-proxy
      forward_auth localhost:4180 {
        uri /oauth2/auth
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Proto {scheme}
      }

      # If auth passes, proxy to backend
      reverse_proxy ${backend} {
        ${proxyHeader}

        # Forward auth headers from oauth2-proxy
        header_up X-Auth-Request-Email {upstream_header.X-Auth-Request-Email}
        header_up X-Auth-Request-User {upstream_header.X-Auth-Request-User}
        header_up X-Auth-Request-Preferred-Username {upstream_header.X-Auth-Request-Preferred-Username}
        header_up X-Auth-Request-Access-Token {upstream_header.X-Auth-Request-Access-Token}
      }

      # Handle auth failures — redirect to login
      handle /oauth2/* {
        reverse_proxy localhost:4180
      }
    }
  '';
in
  # === PUBLIC SERVICES (no auth) ===
  # ai.lan -> llama-server-3090 (host port 1237)
  mkRoute "ai.lan" "http://127.0.0.1:1237" +
  # ai-inference.lan -> AI Gateway (NodePort 30880)
  mkRoute "ai-inference.lan" "http://127.0.0.1:30880" +
  # brain.lan -> Knowledge Fabric API (via Flannel pod IP)
  mkRoute "brain.lan" "http://10.244.1.7:3000" +
  # privacy-filter.lan -> Privacy Filter (via Flannel pod IP)
  mkRoute "privacy-filter.lan" "http://10.244.1.23:8080" +
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
  # Llama.cpp Zephyr 3090 (oauth2-proxy sidecar)
  mkRoute "llama.zephyr.lan" "http://127.0.0.1:4180"
