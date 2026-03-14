# Harmonia Binary Cache for Cluster
# Modern Rust-based binary cache server with compression and TLS
# See: https://github.com/nix-community/harmonia
#
# FEATURES:
# - zstd compression (3-5x smaller nar files)
# - HTTP range support (resumable downloads)
# - Built-in TLS (no reverse proxy needed)
# - Prometheus metrics (/metrics)
# - Optional isolated daemon
#
# USAGE:
#   1. Generate signing key:
#      nix-store --generate-binary-cache-key zephyr-cache-1 \
#        /var/lib/secrets/harmonia.secret \
#        /var/lib/secrets/harmonia.pub
#
#   2. Add to flake.nix inputs:
#      harmonia.url = "github:nix-community/harmonia";
#
#   3. Configure client nodes:
#      nix.settings.substituters = [ "https://zephyr:5000" ];
#      nix.settings.trusted-public-keys = [ "zephyr-cache-1:KEY_HERE" ];
{
  config,
  lib,
  pkgs,
  inputs,
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

  # Note: Harmonia module import must be at the flake level, not here
  # The harmonia input should be imported in the host configuration

  config = lib.mkIf cfg.enable {
    # Use harmonia from nixpkgs
    # Note: harmonia-dev from the flake input provides newer features
    # but requires adding harmonia input to flake.nix
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

    # Firewall
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 5000 ];

    # Systemd hardening
    systemd.services.harmonia = {
      serviceConfig = {
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = ["/nix/store" "/nix/var/nix"];
        PrivateTmp = true;
        NoNewPrivileges = true;
        MemoryLimit = "4G";
      };
    };
  };
}
