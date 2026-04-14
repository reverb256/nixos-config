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
    environment.etc."nixos-auto-update.sh".text = lib.mkIf cfg.enable ''
      #!/usr/bin/env bash

      set -euo pipefail

      if [ -d /run/nixos-shared ] && [ -f /run/nixos-shared/flake.nix ]; then
        FLAKE_PATH=/run/nixos-shared
      elif [ -f /etc/nixos/flake.nix ]; then
        FLAKE_PATH=/etc/nixos
      else
        echo "ERROR: Cannot find flake.nix in /etc/nixos or /run/nixos-shared"
        exit 1
      fi

      LOG_FILE=/var/log/nixos-auto-update.log

      export PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH

      exec >> "$LOG_FILE" 2>&1
      echo "$(date): Starting automatic update"

      AGE_THRESHOLD_DAYS=7
      NOW=$(date +%s)
      LOCK_FILE="$FLAKE_PATH/flake.lock"
      if [ -f "$LOCK_FILE" ]; then
        for input_name in ${lib.concatStringsSep " " cfg.updateFlakeInputs}; do
          INPUT_TS=$(${pkgs.jq}/bin/jq -r ".nodes | to_entries[] | select(.key == \"$input_name\") | .value.lastModified // empty" "$LOCK_FILE" 2>/dev/null || true)
          if [ -n "$INPUT_TS" ] && [ "$INPUT_TS" != "null" ]; then
            AGE_DAYS=$(( (NOW - INPUT_TS) / 86400 ))
            if [ "$AGE_DAYS" -lt "$AGE_THRESHOLD_DAYS" ]; then
              echo "$(date): BLOCKED: $input_name is only $AGE_DAYS days old (threshold: $AGE_THRESHOLD_DAYS days). Skipping update."
              continue
            fi
            echo "$(date): OK: $input_name is $AGE_DAYS days old"
          fi
        done
      fi

      UPDATE_ARGS=""
      for input_name in ${lib.concatStringsSep " " cfg.updateFlakeInputs}; do
          UPDATE_ARGS="$UPDATE_ARGS --update-input $input_name"
      done

      if [ -n "$UPDATE_ARGS" ]; then
          echo "$(date): Updating flake inputs: ${lib.concatStringsSep ", " cfg.updateFlakeInputs}"
          nix flake update $UPDATE_ARGS --flake "$FLAKE_PATH"
      fi

      echo "$(date): Building and switching to new configuration"
      nixos-rebuild switch --flake "$FLAKE_PATH" --option refresh-template-caches true ${lib.concatStringsSep " " cfg.extraFlags}

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
        ExecStart = "${lib.getBin pkgs.bash}/bin/bash /etc/nixos-auto-update.sh";
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
          else cfg.interval;
        Persistent = true;
      };
    };
  };
}
