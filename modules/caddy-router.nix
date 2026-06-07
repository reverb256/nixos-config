{
  config,
  lib,
  pkgs,
  ...
}: let
  # Import port registry for direct NodePort access
  ports = import ../kubernetes/service-ports.nix;

  # Import cluster constants for node IPs
  cluster = import ../kubernetes/cluster.nix;

  # ── TLS certificate paths ────────────────────────────────────────
  tlsCert = "/etc/ssl/cluster-ca/leaf.crt";
  tlsKey = "/etc/ssl/cluster-ca/leaf.key";

  # ── Caddyfile generation helpers (pure functions) ──────────────────
  # These return Caddyfile text, NOT config. Import manually in host configs.

  # Generate forward_auth block
  mkForwardAuth = oauth2Port: ''
    forward_auth 127.0.0.1:${toString oauth2Port} {
      uri /oauth2/auth
      copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username
      handle_response {
        @is401 expression {http.reverse_proxy.status_code} == 401
        redir @is401 https://auth.lan/oauth2/start?rd={scheme}://{host}{uri} temporary
      }
    }
  '';

  # Generate passthrough proxy headers
  mkProxyHeader = ''
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Host {host}
    header_up X-Forwarded-Proto {scheme}
  '';
in {
  options.services.caddy-router = {
    enable = lib.mkEnableOption "Caddy router helpers (makes helpers available)";

    # ── Exported helpers for host configs ──────────────────────────
    helpers = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      internal = true;
      description = "Caddy router helper functions for host configs";
    };
  };

  config = lib.mkIf config.services.caddy-router.enable {
    # Export helper functions so host configs can use them
    services.caddy-router.helpers = {
      inherit ports cluster tlsCert tlsKey;
      mkForwardAuth = mkForwardAuth ports.oauth2-proxy;
      inherit mkProxyHeader;
      mkAuthRoute = hosts: backend: ''
        ${hosts} {
          tls ${tlsCert} ${tlsKey}
          encode zstd gzip
          ${mkForwardAuth ports.oauth2-proxy}
          reverse_proxy ${backend} {
            ${mkProxyHeader}
          }
        }
      '';
      mkRoute = hosts: backend: ''
        ${hosts} {
          tls ${tlsCert} ${tlsKey}
          encode zstd gzip
          reverse_proxy ${backend} {
            ${mkProxyHeader}
          }
        }
      '';
      mkAuthRouteTLS = hosts: backend: ''
        ${hosts} {
          tls ${tlsCert} ${tlsKey}
          encode zstd gzip
          ${mkForwardAuth ports.oauth2-proxy}
          reverse_proxy ${backend} {
            ${mkProxyHeader}
            transport http {
              tls
              tls_insecure_skip_verify
            }
          }
        }
      '';
    };
  };
}
