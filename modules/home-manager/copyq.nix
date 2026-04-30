{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.copyq;
in {
  options.programs.copyq = {
    enable = lib.mkEnableOption "CopyQ - Advanced clipboard manager";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pkgs.copyq];

    # Start CopyQ as a systemd user service - run as daemon directly
    systemd.user.services.copyq = {
      Unit = {
        Description = "CopyQ Clipboard Manager";
        # Start after graphical session
        After = ["graphical-session.target"];
      };
      Service = {
        Type = "simple";
        # Run copyq directly - it will fork to background as daemon
        ExecStart = "${lib.getExe pkgs.copyq}";
        # Restart on failure
        Restart = "on-failure";
        RestartSec = 5;
        # Environment for Wayland
        Environment = "QT_QPA_PLATFORM=wayland";
      };
      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  };
}
