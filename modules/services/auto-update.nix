{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nixos-auto-update;
  inherit
    (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  updateScript = pkgs.writeShellScript "nixos-auto-update" ''
    set -euo pipefail

    PATH=${lib.makeBinPath [
      pkgs.coreutils
      pkgs.gnutar
      pkgs.gzip
      pkgs.jq
      pkgs.nix
      pkgs.kubectl
    ]}

    # Find flake path
    if [ -d /run/nixos-shared ] && [ -f /run/nixos-shared/flake.nix ]; then
      FLAKE_PATH=/run/nixos-shared
    elif [ -f /etc/nixos/flake.nix ]; then
      FLAKE_PATH=/etc/nixos
    else
      echo "WARNING: Cannot find flake.nix in /etc/nixos or /run/nixos-shared"
      exit 0
    fi

    LOG_FILE=/var/log/nixos-auto-update.log
    exec >> "$LOG_FILE" 2>&1

    echo "$(date): Starting automatic update check"

    # --- Age gate: skip if any input is too recent ---
    AGE_THRESHOLD_DAYS=${toString cfg.cooldownDays}
    NOW=$(date +%s)
    LOCK_FILE="$FLAKE_PATH/flake.lock"
    ALL_INPUTS_OLD=true

    if [ -f "$LOCK_FILE" ]; then
      for input_name in ${lib.concatStringsSep " " cfg.updateFlakeInputs}; do
        INPUT_TS=$(
          jq -r \
            ".nodes | to_entries[] | select(.key == \"$input_name\") | .value.lastModified // empty" \
            "$LOCK_FILE" 2>/dev/null || true
        )
        if [ -z "$INPUT_TS" ] || [ "$INPUT_TS" = "null" ]; then
          echo "$(date): WARN: No lastModified for $input_name, skipping age check"
          continue
        fi
        AGE_DAYS=$(( (NOW - INPUT_TS) / 86400 ))
        if [ "$AGE_DAYS" -ge "$AGE_THRESHOLD_DAYS" ]; then
          echo "$(date): OK: $input_name is $AGE_DAYS days old (threshold: $AGE_THRESHOLD_DAYS)"
        else
          echo "$(date): SKIP: $input_name is only $AGE_DAYS days old (threshold: $AGE_THRESHOLD_DAYS)"
          ALL_INPUTS_OLD=false
        fi
      done

      if [ "$ALL_INPUTS_OLD" = "false" ]; then
        echo "$(date): Inputs not old enough, skipping update"
        exit 0
      fi
    fi

    # --- Update flake inputs ---
    UPDATE_ARGS=""
    for input_name in ${lib.concatStringsSep " " cfg.updateFlakeInputs}; do
      UPDATE_ARGS="$UPDATE_ARGS --update-input $input_name"
    done

    if [ -n "$UPDATE_ARGS" ]; then
      echo "$(date): Updating flake inputs: ${lib.concatStringsSep ", " cfg.updateFlakeInputs}"
      nix flake update $UPDATE_ARGS --flake "$FLAKE_PATH"
    fi

    # --- Rebuild ---
    echo "$(date): Running nixos-rebuild ${cfg.rebuildMode} --flake $FLAKE_PATH"
    nixos-rebuild ${cfg.rebuildMode} --flake "$FLAKE_PATH"

    # --- Optional reboot ---
    if [ "${toString cfg.allowReboot}" = "true" ]; then
      echo "$(date): Update applied, draining k3s node before reboot..."
      if command -v kubectl &>/dev/null; then
        kubectl drain $(hostname -s) --ignore-daemonsets --delete-emptydir-data --timeout=60s 2>/dev/null || true
      fi
      reboot
    fi

    echo "$(date): Automatic update completed successfully"
  '';
in {
  options.services.nixos-auto-update = {
    enable = mkEnableOption "Automatic NixOS updates";

    interval = mkOption {
      type = types.str;
      default = "weekly";
      description = ''
        systemd calendar expression for update schedule.
        Examples: "daily", "weekly", "Mon 02:00", "*-*-01 03:00"
      '';
    };

    updateFlakeInputs = mkOption {
      type = types.listOf types.str;
      default = ["nixpkgs"];
      description = "List of flake inputs to update";
    };

    cooldownDays = mkOption {
      type = types.int;
      default = 7;
      description = ''
        Minimum age in days of a flake.lock entry before it will be updated.
        All inputs must exceed this threshold for the update to proceed.
      '';
    };

    rebuildMode = mkOption {
      type = types.enum ["switch" "boot" "test" "build"];
      default = "boot";
      description = ''
        How to apply the rebuild:
        - "boot": stage update for next reboot (safest for unattended)
        - "switch": apply immediately
        - "test": apply but don't persist across reboots
        - "build": only build, don't apply
      '';
    };

    allowReboot = mkOption {
      type = types.bool;
      default = false;
      description = "Reboot after successful update (only useful with rebuildMode=boot)";
    };

    persistent = mkOption {
      type = types.bool;
      default = true;
      description = "Catch up on missed update runs after boot";
    };

    randomizedDelaySec = mkOption {
      type = types.str;
      default = "0";
      description = "Randomize start time within this many seconds";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.nixos-auto-update = {
      description = "Automatic NixOS Update";
      # NOTE: previously `wants/after = run-nixos-shared.mount`, but the
      # nixos-share NFS client is dead cluster-wide (zephyr's NFS server is
      # not enabled), so that dependency made this unit fail at boot.
      # The update script already falls back to /etc/nixos when
      # /run/nixos-shared is absent, so the dependency is dropped.
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = updateScript;
        User = "root";
      };
    };

    systemd.timers.nixos-auto-update = {
      description = "Timer for Automatic NixOS Updates";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = cfg.persistent;
        RandomizedDelaySec = cfg.randomizedDelaySec;
      };
    };

    # Ensure log file exists
    system.activationScripts.nixos-auto-update-log = ''
      touch /var/log/nixos-auto-update.log
      chmod 640 /var/log/nixos-auto-update.log
    '';
  };
}
