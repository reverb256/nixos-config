# Common Caddy configuration module for ingress and systemd services
#
# Usage:
#   services.caddy-common = {
#     enable = true;
#     securityHeaders = true;  # Enable HSTS, CSP, X-Frame-Options, Referrer-Policy
#     rateLimit = 100;         # Requests per minute (window: 1m)
#     metricsPort = 2019;
#     adminListenAddress = "0.0.0.0";  # K8s: 0.0.0.0, systemd: 127.0.0.1
#   };
{ config, lib, pkgs, ... }:
let
  cfg = config.services.caddy-common;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.caddy-common = {
    enable = mkEnableOption "Common Caddy configuration features for ingress";

    securityHeaders = mkOption {
      type = types.bool;
      default = true;
      description = "Enable security headers (HSTS, CSP, X-Frame-Options)";
    };

    rateLimit = mkOption {
      type = types.ints.positive;
      default = 100;
      description = "Rate limit requests per minute (window)";
    };

    metricsPort = mkOption {
      type = types.port;
      default = 2019;
      description = "Prometheus metrics port";
    };

    adminListenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Admin API listen address (0.0.0.0 for K8s, 127.0.0.1 for systemd)";
    };
  };

  config = mkIf cfg.enable {
    services.caddy = {
      globalConfig = ''
        {
          admin ${cfg.adminListenAddress}:${toString cfg.metricsPort}
          default_sni cluster.local

          ${lib.optionalString cfg.securityHeaders ''
          (security_headers) {
            header {
              Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
              X-Content-Type-Options "nosniff"
              X-Frame-Options "SAMEORIGIN"
              X-XSS-Protection "1; mode=block"
              Referrer-Policy "strict-origin-when-cross-origin"
              Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob: https:"
              -Server
            }
          }
          ''}

          rate_limit {
            zone dynamic_zones {
              entry {
                zone = "cluster_local"
                key = "remote_ip"
                events = ${toString cfg.rateLimit}
                window = 1m
              }
            }
          }

          encode zstd gzip
        }
      '';
    };
  };
}
