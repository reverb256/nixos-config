# Caprine Home Manager Configuration
# Elegant Facebook Messenger desktop app
# Uses Nixpkgs instead of Flatpak for better Wayland integration
# Auto-detects best backend (Wayland or XWayland)
{
  config,
  lib,
  pkgs,
  ...
}: {
  options.caprine.enable = lib.mkEnableOption "Caprine Facebook Messenger";

  config = lib.mkIf config.caprine.enable {
    # Install Caprine package
    home.packages = with pkgs; [caprine];

    # Autostart Caprine on login
    # Global ELECTRON_OZONE_PLATFORM_HINT=auto handles backend selection
    systemd.user.services.caprine-autostart = {
    Unit = {
      Description = "Caprine - Facebook Messenger autostart";
      After = [
        "graphical-session-pre.target"
        "plasma-plasmashell.service"
      ];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.caprine}/bin/caprine";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
  };
}
