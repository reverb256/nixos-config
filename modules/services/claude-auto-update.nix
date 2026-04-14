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
      services = {
        update-claude-native = {
          description = "Update Claude Code to latest version";
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            WorkingDirectory = "/etc/nixos";
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

              nix flake lock --update-input claude-native

              if git diff --quiet flake.lock 2>/dev/null; then
                echo "[$(date)] No updates available"
                exit 0
              fi

              echo "[$(date)] Updated claude-native!"

              git diff flake.lock | grep "claude-native" || true

              git add flake.lock
              git commit -m "chore: update claude-native to latest version"

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
        update-claude-native = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.interval;
            Persistent = true;
          };
        };
      };

      user = {
        services = {
          update-claude-user-profile = {
            description = "Update Claude Code in user profile";
            serviceConfig = {
              Type = "oneshot";
              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              RestrictRealtime = true;
              ExecStart = pkgs.writeShellScript "update-claude-user-profile" ''
                #!/bin/sh
                set -euo pipefail

                echo "[$(date)] Updating claude-code in user profile..."

                if ! nix profile list | grep -q claude-code; then
                  echo "[$(date)] claude-code not in user profile, skipping"
                  exit 0
                fi

                nix profile upgrade claude-code

                echo "[$(date)] User profile updated!"
              '';
            };
          };
        };

        timers = {
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
