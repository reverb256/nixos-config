{ config, lib, pkgs, ... }:

let
  cfg = config.services.nixos-free-tier;
in {
  options.services.nixos-free-tier = {
    enable = lib.mkEnableOption "Automatic cleanup to stay within free tier limits";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "Cleanup interval (daily, weekly, monthly)";
    };

    maxGenerations = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = "Maximum system generations to keep";
    };

    deleteOlderThan = lib.mkOption {
      type = lib.types.str;
      default = "30d";
      description = "Delete generations older than this (e.g., 30d, 7d)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nixos-free-tier-cleanup = {
      description = "NixOS Free Tier Cleanup";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeScript "free-tier-cleanup" ''
          #!/usr/bin/env bash
          set -e
          
          # Delete old generations
          ${pkgs.nix}/bin/nix-collect-garbage --delete-older-than ${cfg.deleteOlderThan}
          
          # Optimize store
          ${pkgs.nix}/bin/nix-store --optimise
          
          # Log completion
          echo "$(date): Free tier cleanup completed"
        '';
      };
    };

    systemd.timers.nixos-free-tier-cleanup = {
      description = "Timer for NixOS Free Tier Cleanup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
      };
    };

    # Also add automatic generation limit
    nix.settings = {
      # Keep only recent generations to save space
      auto-optimise-store = true;
    };

    system.autoUpgrade.flags = [
      "--max-jobs" "2"
      "--cores" "2"
    ];
  };
}
