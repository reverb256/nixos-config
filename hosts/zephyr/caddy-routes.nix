{cluster}: let
  # Import the centralized port registry (single source of truth)
  ports = import ../../kubernetes/service-ports.nix;

  # Node IPs — derived from the cluster option (set by network-constants.nix from cluster.nix)
  zephyr = cluster.hosts.zephyr.ip or "10.1.1.110";
  nexus = cluster.hosts.nexus.ip or "10.1.1.120";
  forge = cluster.hosts.forge.ip or "10.1.1.130";

  tls = "tls /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key";
  proxyHeader = ''
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Host {host}
    header_up X-Forwarded-Proto {scheme}
  '';
  # Public routes — no auth required
  # Rate limited: 100 req/min per IP (defense-in-depth for funnel-exposed routes).
  # Requires caddy-with-modules (mholt/caddy-ratelimit plugin).
  mkRoute = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip
      rate_limit {
        zone lan_per_ip {
          key    {remote_host}
          events 100
          window 1m
        }
      }
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
  # Rate limited: 100 req/min per IP (defense-in-depth for funnel-exposed routes).
  # Requires caddy-with-modules (mholt/caddy-ratelimit plugin).
  mkAuthRoute = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip
      rate_limit {
        zone lan_auth_per_ip {
          key    {remote_host}
          events 100
          window 1m
        }
      }
      forward_auth 127.0.0.1:${toString ports.oauth2-proxy} {
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
        header_up X-Forwarded-For ${zephyr}
        header_up X-Real-IP ${zephyr}
      }
    }
  '';
  # Protected route for HTTPS backends (haven uses self-signed cert).
  # Rate limited: 100 req/min per IP (defense-in-depth for funnel-exposed routes).
  # Requires caddy-with-modules (mholt/caddy-ratelimit plugin).
  mkAuthRouteTLS = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip
      rate_limit {
        zone lan_tls_per_ip {
          key    {remote_host}
          events 100
          window 1m
        }
      }
      forward_auth 127.0.0.1:${toString ports.oauth2-proxy} {
        uri /oauth2/auth
        copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username
        handle_response {
          @is401 expression {http.reverse_proxy.status_code} == 401
          redir @is401 https://auth.lan/oauth2/start?rd={scheme}://{host}{uri} temporary
        }
      }
      reverse_proxy ${backend} {
        ${proxyHeader}
        header_up X-Forwarded-For ${zephyr}
        header_up X-Real-IP ${zephyr}
        transport http {
          tls
          tls_insecure_skip_verify
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
  # NOTE: Uses NodePort IPs instead of ClusterIP DNS because CoreDNS cluster.local
  # is not resolvable from the host (unbound forwards to public DNS).
  "auth.lan {
      ${tls}
      encode zstd gzip
      rate_limit {
        zone auth_per_ip {
          key    {remote_host}
          events 100
          window 1m
        }
      }
      # OAuth2 callback — proxy to oauth2-proxy (NOT Casdoor)
      handle /oauth2/* {
        reverse_proxy ${zephyr}:${toString ports.oauth2-proxy}
      }
      handle {
        reverse_proxy ${zephyr}:${toString ports.casdoor} {
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
  mkRoute "searxng.lan, search.lan" "http://${nexus}:${toString ports.searxng}"
  + "\n"
  +
  # === PROTECTED SERVICES (central SSO) ===
  # AI Inference Gateway — OpenAI-compatible API
  mkAuthRoute "ai-inference.lan" "http://${nexus}:${toString ports.ai-inference-gateway}"
  + "\n"
  +
  # Qdrant vector database
  mkAuthRoute "qdrant.lan" "http://${nexus}:${toString ports.qdrant}"
  + "\n"
  +
  # Mission Control
  mkAuthRoute "mission-control.lan" "http://${nexus}:${toString ports.mission-control}"
  + "\n"
  +
  + "\n"
  +
  # Grafana
  mkAuthRoute "grafana.lan" "http://${nexus}:${toString ports.grafana}"
  + "\n"
  +
  # Open WebUI — has own auth (does NOT consume X-Auth-Request-* headers)
  mkRoute "openwebui.lan" "http://${nexus}:${toString ports.open-webui}"
  + "\n"
  # Glance Dashboard (nexus, NodePort 32200)
  + mkRoute "dashboard.lan" "http://${nexus}:${toString ports.glance}"
  + "\n"
  + mkRoute "privacy-filter.lan" "http://${nexus}:${toString ports.privacy-filter}"
  # NOTE: MapleSpike routes handled by Nexus (VIP 10.1.1.100)
  # See /etc/nixos/hosts/nexus/services.nix cluster-services.maplespike-*
  + mkRoute "gitea.lan" "http://${nexus}:${toString ports.gitea}"
  # Hermes Workspace (zephyr, port 3002)
  # Dev environment
  + mkRoute "dev.maplespike.lan" "http://${nexus}:${toString ports.dev-maplespike-portal}"
  + "\n"
  + mkRoute "dev-api.maplespike.lan" "http://${nexus}:${toString ports.dev-maplespike-api}"
  + "\n"
  + mkRoute "dev-mcp.maplespike.lan" "http://${nexus}:${toString ports.dev-maplespike-mcp}"
  + "\n"
  + mkAuthRoute "workspace.lan" "http://127.0.0.1:3002"
  + "\n"
