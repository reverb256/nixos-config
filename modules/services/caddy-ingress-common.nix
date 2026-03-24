# Caddy Ingress Common Configuration Module
# Shared configuration patterns for Kubernetes Caddy ingress manifests
{ config, lib, pkgs, ... }:
let
  cfg = config.services.caddy-ingress-common;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.caddy-ingress-common = {
    enable = mkEnableOption "Common Caddy ingress configuration for Kubernetes manifests";

    securityHeaders = mkOption {
      type = types.bool;
      default = true;
      description = "Enable security headers (HSTS, CSP, X-Frame-Options, Referrer-Policy)";
    };

    rateLimit = mkOption {
      type = types.ints.positive;
      default = 100;
      description = "Rate limit requests per minute (window: 1m)";
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
    # This module provides configuration templates for Kubernetes manifests
    # It does not directly configure systemd services
    # Use the following snippets in kubernetes-manifests/ingress/02-configmap.yaml:

    # Security headers snippet:
    # (security_headers) {
    #   header {
    #     Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    #     X-Content-Type-Options "nosniff"
    #     X-Frame-Options "SAMEORIGIN"
    #     X-XSS-Protection "1; mode=block"
    #     Referrer-Policy "strict-origin-when-cross-origin"
    #     Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob: https:"
    #     -Server
    #   }
    # }

    # Rate limiting snippet (in global options):
    # rate_limit {
    #   zone dynamic_zones {
    #     entry {
    #       zone = "cluster_local"
    #       key = "remote_ip"
    #       events = 100
    #       window = 1m
    #     }
    #   }
    # }

    # Compression snippet (in global options):
    # encode zstd gzip

    # Usage in route blocks:
    # service.cluster.local {
    #   import security_headers
    #   tls internal
    #   reverse_proxy backend.namespace.svc.cluster.local:port
    # }
  };
}
