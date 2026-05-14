{cluster}: let
  # Import the centralized port registry (single source of truth)
  ports = import /etc/nixos/kubernetes/service-ports.nix;
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
  # handle_response inside forward_auth intercepts 401 BEFORE it reaches the client.
  # handle_errors does NOT work here — forward_auth 401 goes through the normal
  # response path, not the error path.
  mkAuthRoute = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip
      forward_auth 127.0.0.1:30890 {
        uri /oauth2/auth
        copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username
        handle_response {
          @is401 expression {http.reverse_proxy.status_code} == 401
          redir @is401 https://auth.lan/oauth2/start?rd={scheme}://{host}{uri} temporary
        }
      }
      reverse_proxy ${backend} {
        ${proxyHeader}
        # Override XFF/X-Real-IP to Caddy IP (MC does exact string match, not CIDR)
        header_up X-Forwarded-For 10.1.1.110
        header_up X-Real-IP 10.1.1.110
      }
    }
  '';
  # Protected route for HTTPS backends (haven uses self-signed cert).
  mkAuthRouteTLS = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip
      forward_auth 127.0.0.1:30890 {
        uri /oauth2/auth
        copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username
        handle_response {
          @is401 expression {http.reverse_proxy.status_code} == 401
          redir @is401 https://auth.lan/oauth2/start?rd={scheme}://{host}{uri} temporary
        }
      }
      reverse_proxy ${backend} {
        ${proxyHeader}
        header_up X-Forwarded-For 10.1.1.110
        header_up X-Real-IP 10.1.1.110
        transport http {
          tls
          tls_insecure_skip_verify
        }
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
  mkRoute "vaultwarden.lan" "http://${nexus}:${toString ports.vaultwarden}"
  + "\n"
  +
  # n8n automation — has own auth
  mkRoute "n8n.lan" "http://${nexus}:${toString ports.n8n}"
  + "\n"
  +
  # Search (SearXNG) — public search tool
  mkRoute "searxng.lan, search.lan" "http://${zephyr}:32081"
  + "\n"
  +
  # === PROTECTED SERVICES (central SSO) ===
  # Haven (HTTPS backend, self-signed cert — needs tls_insecure_skip_verify)
  mkAuthRouteTLS "haven.lan" "https://${nexus}:32100"
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
  # Open WebUI — has own auth (does NOT consume X-Auth-Request-* headers)
  mkRoute "openwebui.lan" "http://${nexus}:32080"
  + "\n"
  # Glance Dashboard (nexus, NodePort 32200)
  + mkRoute "dashboard.lan" "http://${nexus}:${toString ports.glance}"
  + "\n"
  + mkRoute "frostbite-mcp.lan" "http://${nexus}:${toString ports.frostbite-mcp}"
  + mkRoute "maplespike-mcp.lan" "http://${nexus}:${toString ports.maplespike-mcp}"
  + "\n"
  + mkRoute "maplespike-api.lan" "http://${nexus}:${toString ports.maplespike-api}"
  + "\n"
+ mkRoute "maplespike.lan" "http://${nexus}:${toString ports.maplespike-portal}"
  + mkRoute "status.maplespike.lan" "http://${nexus}:${toString ports.maplespike-status}"
  + mkRoute "gitea.lan" "http://${nexus}:${toString ports.gitea}"
  # Hermes Workspace (zephyr, port 3002)
  # Dev environment
  + mkRoute "dev.maplespike.lan" "http://${nexus}:${toString ports.dev-maplespike-portal}"
  + "\n"
  + mkRoute "dev-maplespike-api.lan" "http://${nexus}:${toString ports.dev-maplespike-api}"
  + "\n"
  + mkRoute "dev-maplespike-mcp.lan" "http://${nexus}:${toString ports.dev-maplespike-mcp}"
  + "\n"
  + mkAuthRoute "workspace.lan" "http://127.0.0.1:3002"
  + "\n"