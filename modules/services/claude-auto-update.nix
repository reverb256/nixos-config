# Claude Code Auto-Update Service
# Automatically updates claude-native input and rebuilds when new versions are available
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.claude-auto-update;
in {
  options.services.claude-auto-update = {
    enable = lib.mkEnableOption "Claude Code automatic updates";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      example = "hourly";
      description = "How often to check for updates (systemd calendar format)";
    };

    autoRebuild = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "Whether to automatically rebuild after updating inputs";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      # System services and timers
      services = {
        # Service to update claude-native
        update-claude-native = {
          description = "Update Claude Code to latest version";
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            WorkingDirectory = "/etc/nixos";
            # Security hardening
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            RestrictRealtime = true;
            ReadWritePaths = ["/etc/nixos" "/var/lib/nixos"];
            ExecStart = pkgs.writeShellScript "update-claude-native" ''
              #!/bin/sh
              set -euo pipefail

              echo "[$(date)] Checking for Claude Code updates..."

              # Update claude-native input
              nix flake lock --update-input claude-native

              # Check if there were actual updates
              if git diff --quiet flake.lock 2>/dev/null; then
                echo "[$(date)] No updates available"
                exit 0
              fi

              echo "[$(date)] Updated claude-native!"

              # Show what changed
              git diff flake.lock | grep "claude-native" || true

              # Commit the update
              git add flake.lock
              git commit -m "chore: update claude-native to latest version"

              # Optionally rebuild
              ${lib.optionalString cfg.autoRebuild ''
                echo "[$(date)] Rebuilding system..."
                nixos-rebuild switch --flake .
              ''}

              echo "[$(date)] Update complete!"
            '';
          };
        };
      };

      timers = {
        # Timer for automatic updates
        update-claude-native = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.interval;
            Persistent = true;
          };
        };
      };

      # User services and timers
      user = {
        services = {
          # User profile update service (runs as user)
          update-claude-user-profile = {
            description = "Update Claude Code in user profile";
            serviceConfig = {
              Type = "oneshot";
              # Security hardening
              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              RestrictRealtime = true;
              ExecStart = pkgs.writeShellScript "update-claude-user-profile" ''
                #!/bin/sh
                set -euo pipefail

                echo "[$(date)] Updating claude-code in user profile..."

                # Check if claude-code is in profile
                if ! nix profile list | grep -q claude-code; then
                  echo "[$(date)] claude-code not in user profile, skipping"
                  exit 0
                fi

                # Upgrade claude-code to latest
                nix profile upgrade claude-code

                echo "[$(date)] User profile updated!"
              '';
            };
          };
        };

        timers = {
          # User timer for profile updates
          update-claude-user-profile = {
            wantedBy = ["timers.target"];
            timerConfig = {
              OnCalendar = cfg.interval;
              Persistent = true;
            };
          };
        };
      };
    };
  };
}
