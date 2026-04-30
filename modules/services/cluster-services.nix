{
  config,
  lib,
  pkgs,
  ...
}: let
  cluster = config.networking.cluster;
  cfg = config.services.cluster-services;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mapAttrsToList
    concatStringsSep
    ;

  # Build Caddy virtualHost blocks from the service registry
  buildCaddyBlocks = services:
    concatStringsSep "\n" (
      mapAttrsToList (_name: svc: ''
        https://${svc.domain} {
          tls ${cfg.tlsCert} ${cfg.tlsKey}
          ${lib.optionalString (svc.compress or true) "encode zstd gzip"}
          reverse_proxy ${svc.backend}
        }
      '')
      services
    );

  # Build the full Caddyfile from registry + extra preamble
  buildCaddyfile = services: let
    preamble = ''
      {
        admin 127.0.0.1:2019
        default_sni cluster.local
      }
    '';
    blocks = buildCaddyBlocks services;
  in
    preamble + "\n" + blocks;

  # Build the svc CLI tool
  buildSvcScript = services:
    pkgs.writeShellScriptBin "svc" ''
      set -euo pipefail
      echo "=== Cluster Services (ingress: ${cfg.ingressIP}) ==="
      echo ""
      ${concatStringsSep "\n" (
        mapAttrsToList (_name: svc: ''
          echo "  https://${svc.domain} -> ${svc.backend}"
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
      default = "/etc/ssl/cluster-ca/leaf.crt";
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
          };
        }
      );
      default = {};
      description = "Service registry — each entry generates a Caddy virtualHost";
    };
  };

  config = mkIf cfg.enable {
    # Generate Caddy config from registry
    services.caddy = {
      enable = true;
      configFile = pkgs.writeText "Caddyfile" (buildCaddyfile cfg.services);
    };

    # svc CLI tool
    environment.systemPackages = [
      (buildSvcScript cfg.services)
    ];
  };
}
