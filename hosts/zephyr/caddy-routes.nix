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
      forward_auth 127.0.0.1:30890 {
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

  # Node IPs
  nexus = "10.1.1.120";
  forge = "10.1.1.130";
  zephyr = "10.1.1.110";
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
  # NOTE: Uses NodePort IPs instead of ClusterIP DNS because CoreDNS cluster.local
  # is not resolvable from the host (unbound forwards to public DNS).
  "auth.lan {
      ${tls}
      encode zstd gzip

      # OAuth2 callback — proxy to oauth2-proxy (NOT Casdoor)
      handle /oauth2/* {
        reverse_proxy ${zephyr}:30890
      }

      handle {
        reverse_proxy ${zephyr}:32556 {
          ${proxyHeader}
        }
      }
    }"
  + "\n"
  +

  # Vaultwarden — has own auth
  mkRoute "vaultwarden.lan" "http://${nexus}:32110"
  + "\n"
  +

  # n8n automation — has own auth
  mkRoute "n8n.lan" "http://${nexus}:32127"
  + "\n"
  +

  # Search (SearXNG) — public search tool
  mkRoute "searxng.lan, search.lan" "http://${zephyr}:32081"
  + "\n"
  +

  # === PROTECTED SERVICES (central SSO) ===
  # Haven (HTTPS backend, skip verification)
  "haven.lan {
      ${tls}
      encode zstd gzip

      forward_auth ${zephyr}:30890 {
        uri /oauth2/auth
        copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username
      }

      handle_errors 4xx {
        @is401 {
          expression {http.error.status_code} == 401
        }
        redir @is401 https://auth.lan/oauth2/start?rd={scheme}://{host}{uri} 302
      }

      reverse_proxy https://${nexus}:32100 {
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
  mkAuthRoute "ai-inference.lan" "http://${nexus}:30880"
  + "\n"
  +

  # Brain / Knowledge Fabric API
  mkAuthRoute "brain.lan" "http://${nexus}:31180"
  + "\n"
  +

  # Qdrant vector database
  mkAuthRoute "qdrant.lan" "http://${nexus}:30632"
  + "\n"
  +

  # Mission Control
  mkAuthRoute "mission-control.lan" "http://${nexus}:32101"
  + "\n"
  +

  # Kagent controller
  mkAuthRoute "kagent.lan" "http://${nexus}:30794"
  + "\n"
  +

  # Grafana
  mkAuthRoute "grafana.lan" "http://${nexus}:32102"
  + "\n"
  +

  # Open WebUI
  mkAuthRoute "openwebui.lan" "http://${nexus}:32080"
  + "\n"
  +

  # Hermes Workspace (zephyr, port 3002)
  mkAuthRoute "workspace.lan" "http://127.0.0.1:3002"
  + "\n"
  + ""
