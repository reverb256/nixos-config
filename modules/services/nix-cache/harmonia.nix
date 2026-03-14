# Harmonia Binary Cache for Cluster
# Modern Rust-based binary cache server with compression and TLS
# See: https://github.com/nix-community/harmonia
#
# This is a simple wrapper that configures harmonia from nixpkgs
# For the full harmonia flake with latest features, add to flake.nix:
#   harmonia.url = "github:nix-community/harmonia";
# And import: inputs.harmonia.nixosModules.harmonia
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nix-cache.harmonia;
in {
  options.services.nix-cache.harmonia = {
    enable = lib.mkEnableOption "Harmonia binary cache server";

    signKeyPaths = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
      description = "Paths to signing keys (generated via nix-store --generate-binary-cache-key)";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "[::]:5000";
      description = "Address to bind to";
    };

    workers = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Number of worker threads";
    };

    enableCompression = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable zstd compression (3-5x smaller transfers)";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall for Harmonia port";
    };

    priority = lib.mkOption {
      type = lib.types.int;
      default = 40;
      description = "Cache priority (higher than nixos.org's 30)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Harmonia binary cache from nixpkgs
    services.harmonia.cache = {
      enable = true;
      signKeyPaths = cfg.signKeyPaths;
      settings = {
        bind = cfg.bindAddress;
        workers = cfg.workers;
        enable_compression = cfg.enableCompression;
        priority = cfg.priority;
      };
    };

    # Firewall for Harmonia port
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 5000 ];

    # Systemd hardening for harmonia
    systemd.services.harmonia.serviceConfig = {
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = ["/nix/store" "/nix/var/nix"];
      PrivateTmp = true;
      NoNewPrivileges = true;
      MemoryLimit = "4G";
    };
  };
}
