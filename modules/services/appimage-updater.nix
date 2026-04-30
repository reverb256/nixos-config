{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.appimage-updater;
  script = "${../../scripts/auto-update-appimages.sh}";
in {
  options.services.appimage-updater = {
    enable = lib.mkEnableOption "Automatic AppImage package updater (Stability Matrix, LM Studio)";
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "Mon *-*-* 04:00:00";
      description = "systemd timer OnCalendar expression (default: weekly Monday 4AM)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.appimage-updater = {
      description = "Auto-update AppImage Nix packages (Stability Matrix, LM Studio)";
      path = with pkgs; [
        curl
        git
        nix
        python3
        gnumake
        coreutils
        gnugrep
        gnused
        bash
        util-linux
      ];
      environment = {
        NIX_PATH = "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos";
        HOME = "/root";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = script;
        User = "root";
        StandardOutput = "journal";
        StandardError = "journal";
        TimeoutStartSec = "600";
        # Need network for API calls and nix builds
        PrivateNetwork = false;
        # Need write access to /etc/nixos git repo
        ReadWritePaths = ["/etc/nixos"];
      };
    };

    systemd.timers.appimage-updater = {
      description = "Weekly auto-update check for AppImage packages";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
    };
  };
}
