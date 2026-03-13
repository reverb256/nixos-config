# NixOS Auto-Build Service
# Nightly builds for cluster nodes to populate binary cache
# Inspired by https://www.nijho.lt/post/nixos-cache/
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nix-cache.auto-build;
in {
  options.services.nix-cache.auto-build = {
    enable = lib.mkEnableOption "Nightly auto-build for cluster nodes";

    flakePath = lib.mkOption {
      type = lib.types.path;
      default = "/etc/nixos";
      description = "Path to the NixOS flake configuration";
    };

    buildTime = lib.mkOption {
      type = lib.types.str;
      default = "02:00";
      description = "Time to run builds (systemd timer format)";
    };

    revDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/nix-auto-build";
      description = "Directory to store .rev files";
    };

    nodes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["zephyr" "nexus" "sentry"];
      description = "Nodes to build configurations for";
    };

    cores = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Number of cores for builds (conservative for stability)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create rev directory
    systemd.tmpfiles.rules = [
      "d ${cfg.revDir} 0755 root root -"
    ];

    # Auto-build script
    environment.etc."nix-auto-build.sh" = {
      mode = "0755";
      text = ''
        #!/bin/bash
        set -euo pipefail

        FLAKE_DIR="''${FLAKE_PATH:-/etc/nixos}"
        REV_DIR="''${REV_DIR:-/var/lib/nix-auto-build}"
        NODES="''${NODES:-zephyr nexus sentry}"
        CORES="''${CORES:-1}"

        echo "[nix-auto-build] Starting builds at $(date)"

        # Update flake lock
        echo "[nix-auto-build] Updating flake.lock..."
        cd "$FLAKE_DIR"
        nix flake update

        # Extract nixpkgs revision
        NIXPKGS_REV=$(nix flake metadata --json | jq -r '.locks.nodes.nixpkgs.filtered.revision')
        echo "[nix-auto-build] nixpkgs revision: $NIXPKGS_REV"

        # Build each node configuration
        for node in $NODES; do
          echo "[nix-auto-build] Building $node..."

          # Build with conservative settings
          nix build .#nixosConfigurations.$node.config.system.build.toplevel \
            --override-input nixpkgs github:NixOS/nixpkgs/$NIXPKGS_REV \
            --cores $CORES \
            --max-jobs $CORES \
            --print-build-logs \
            --keep-going || {
            echo "[nix-auto-build] FAILED: $node"
            continue
          }

          # Save revision file for this node (will be shared via nixos-share)
          echo "$NIXPKGS_REV" > "$REV_DIR/$node.rev"
          echo "[nix-auto-build] ✓ $node (rev: ''${NIXPKGS_REV:0:8})"
        done

        echo "[nix-auto-build] Complete at $(date)"
      '';
    };

    # Systemd service
    systemd.services.nix-auto-build = {
      description = "NixOS auto-build service";
      after = ["network-online.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/nix-auto-build.sh";

        # Build environment
        Environment = [
          "FLAKE_PATH=${cfg.flakePath}"
          "REV_DIR=${cfg.revDir}"
          "NODES=${lib.concatStringsSep " " cfg.nodes}"
          "CORES=${toString cfg.cores}"
        ];

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "nix-auto-build";
      };
    };

    # Systemd timer - runs daily at specified time
    systemd.timers.nix-auto-build = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.buildTime;
        Persistent = true;
      };
    };
  };
}
