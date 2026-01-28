{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nixos-auto-update;
in {
  options = {
    services.nixos-auto-update = {
      enable = lib.mkEnableOption "Automatic NixOS updates";

      interval = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
        description = ''
          Update interval for systemd timer. Options include:
          - daily
          - weekly
          - monthly
          Or use full systemd calendar syntax like "Sun 02:00"
        '';
      };

      extraFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["--upgrade-all"];
        description = "Extra flags to pass to nixos-rebuild";
      };

      updateFlakeInputs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["nixpkgs"];
        example = ["nixpkgs" "home-manager"];
        description = "List of flake inputs to update automatically";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Create the auto-update script
    environment.etc."nixos-auto-update.sh".source =
      pkgs.writeScript "nixos-auto-update.sh" ''
        #!/usr/bin/env bash
              
        set -euo pipefail
              
        FLAKE_PATH=''
      /etc/nixos ''
        LOG_FILE=/var/log/nixos-auto-update.log

        exec >> "$LOG_FILE" 2>&1
        echo "$(date): Starting automatic update"

        # Pull and update specified flake inputs
        UPDATE_ARGS=""
        for input_name in ${lib.concatStringsSep " " cfg.updateFlakeInputs}; do
            UPDATE_ARGS="$UPDATE_ARGS --update-input $input_name"
        done

        if [ -n "$UPDATE_ARGS" ]; then
            echo "$(date): Updating flake inputs: ${lib.concatStringsSep ", " cfg.updateFlakeInputs}"
            nix flake update $UPDATE_ARGS --flake "$FLAKE_PATH"
        fi

        # Build and switch to the new configuration
        echo "$(date): Building and switching to new configuration"
        nixos-rebuild switch --flake "$FLAKE_PATH" --option refresh-template-caches true ''${cfg.extraFlags[*]}

        echo "$(date): Automatic update completed successfully"
      '';

    systemd.services.nixos-auto-update = {
      description = "Automatic NixOS Update Service";
      unitConfig = {
        "Description" = "Automatic NixOS Update Service";
        "After" = ["network.target"];
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/nixos-auto-update.sh";
        User = "root";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.timers.nixos-auto-update = {
      description = "Timer for Automatic NixOS Updates";
      wantedBy = ["timers.target"];

      timerConfig = {
        OnCalendar =
          if cfg.interval == "daily"
          then "daily"
          else if cfg.interval == "weekly"
          then "weekly"
          else if cfg.interval == "monthly"
          then "monthly"
          else cfg.interval; # Assume it's a custom calendar specification
        Persistent = true;
      };
    };
  };
}
