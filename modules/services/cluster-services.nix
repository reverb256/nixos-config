{
  config,
  lib,
  pkgs,
  ...
}: let
  cluster = config.networking.cluster;
  cfg = config.services.cluster-services;
  authCfg = config.services.central-auth;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mapAttrsToList
    concatStringsSep
    optionalString
    ;

  # Build a public (no auth) Caddy virtualHost block
  # Rate limited: 100 req/min per IP (defense-in-depth for funnel-exposed routes).
  # Requires caddy-with-modules (mholt/caddy-ratelimit plugin).
  # HTTP redirect: force HTTPS for all public services.
  mkPublicBlock = svc: ''
    http://${svc.domain} {
      redir https://{host}{uri} permanent
    }

    https://${svc.domain} {
      tls ${cfg.tlsCert} ${cfg.tlsKey}
      ${optionalString (svc.compress or true) "encode zstd gzip"}
      rate_limit {
        zone ${svc.domain}_per_ip {
          key    {remote_host}
          events 100
          window 1m
        }
      }
      reverse_proxy ${svc.backend}
    }
  '';

  # Build a protected Caddy virtualHost block with forward_auth
  # Uses the expanded form from Caddy docs: reverse_proxy with handle_response
  # Rate limited: 100 req/min per IP (defense-in-depth for funnel-exposed routes).
  # Requires caddy-with-modules (mholt/caddy-ratelimit plugin).
  mkProtectedBlock = svc: ''
    https://${svc.domain} {
      tls ${cfg.tlsCert} ${cfg.tlsKey}
      ${optionalString (svc.compress or true) "encode zstd gzip"}

      rate_limit {
        zone ${svc.domain}_auth_per_ip {
          key    {remote_host}
          events 100
          window 1m
        }
      }

      handle /oauth2/* {
        reverse_proxy 127.0.0.1:${toString authCfg.port}
      }

      handle {
        reverse_proxy 127.0.0.1:${toString authCfg.port} {
          method GET
          rewrite /oauth2/auth

          header_up X-Forwarded-Host {host}
          header_up X-Forwarded-Method {method}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Uri {uri}

          @auth_ok status 2xx
          handle_response @auth_ok {
            request_header X-Auth-Request-User {rp.header.X-Auth-Request-User}
            request_header X-Auth-Request-Email {rp.header.X-Auth-Request-Email}
            request_header X-Auth-Request-Preferred-Username {rp.header.X-Auth-Request-Preferred-Username}
            request_header X-Auth-Request-Access-Token {rp.header.X-Auth-Request-Access-Token}

            reverse_proxy ${svc.backend}
          }

          # On auth failure (401), redirect to SSO login
          @unauth status 401
          handle_response @unauth {
            redir /oauth2/start?rd={scheme}://{host}{uri} 302
          }
        }
      }
    }
  '';

  # Route each service to the correct block builder
  buildCaddyBlock = _name: svc:
    if svc.rawBlock != null
    then svc.rawBlock
    else if svc.protected or false
    then mkProtectedBlock svc
    else mkPublicBlock svc;

  buildCaddyfile = services: let
    preamble = ''
      {
        admin 127.0.0.1:2019
        auto_https off
        default_sni cluster.local
      }
    '';
    blocks = concatStringsSep "\n" (mapAttrsToList buildCaddyBlock services);
  in
    preamble + "\n" + blocks;

  buildSvcScript = services:
    pkgs.writeShellScriptBin "svc" ''
      set -euo pipefail
      echo "=== Cluster Services (ingress: ${cfg.ingressIP}) ==="
      echo ""
      ${concatStringsSep "\n" (
        mapAttrsToList (_name: svc: ''
          proto=$(${lib.getExe pkgs.gnugrep} -q "protected" <<< "${optionalString (svc.protected or false) "protected"}" && echo "🔒" || echo "  ")
          echo "  $proto https://${svc.domain} -> ${svc.backend}"
        '')
        services
      )}
      echo ""
      echo "Total: ${toString (builtins.length (builtins.attrNames services))}"
    '';
in {
  options.services.cluster-services = {
    enable = mkEnableOption "Cluster service registry — single source of truth for Caddy virtualHosts";

    ingressIP = mkOption {
      type = types.str;
      default = cluster.hosts.nexus.ip;
      description = "IP address of the TLS ingress (Caddy) host";
    };

    tlsCert = mkOption {
      type = types.str;
      default = "/etc/ssl/cluster-ca/fullchain.crt";
      description = "Path to TLS leaf certificate";
    };

    tlsKey = mkOption {
      type = types.str;
      default = "/etc/ssl/cluster-ca/leaf.key";
      description = "Path to TLS leaf private key";
    };

    services = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            domain = mkOption {
              type = types.str;
              description = "Fully qualified domain name (e.g., hermes.lan)";
            };

            backend = mkOption {
              type = types.str;
              description = "Backend address (host:port or ClusterIP:port)";
            };

            compress = mkOption {
              type = types.bool;
              default = true;
              description = "Enable zstd+gzip compression";
            };

            protected = mkOption {
              type = types.bool;
              default = false;
              description = "Require SSO authentication via central-auth";
            };

            rawBlock = mkOption {
              type = types.nullOr types.lines;
              default = null;
              description = "Complete Caddy virtualHost block (replaces auto-generated block). Use for path-based routing or other custom config.";
            };
          };
        }
      );
      default = {};
      description = "Service registry — each entry generates a Caddy virtualHost";
    };
  };

  config = mkIf cfg.enable {
    services.caddy = {
      enable = true;  # Re-enabled: moved from zephyr to nexus
      package = pkgs.caddy-with-modules;
      configFile = pkgs.writeText "Caddyfile" (buildCaddyfile cfg.services);
      user = lib.mkForce "root";
      group = lib.mkForce "root";
    };

    # Allow Caddy to bind privileged ports (<1024) when running as non-root
    # Restart=always: survives clean POST /stop to admin API and any unexpected exit
    systemd.services.caddy.serviceConfig = {
      User = "root";
      Group = "root";
      NoNewPrivileges = lib.mkForce false;
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce "5s";
      StartLimitBurst = lib.mkForce 5;
    };

    environment.systemPackages = [
      (buildSvcScript cfg.services)
    ];
  };
}
