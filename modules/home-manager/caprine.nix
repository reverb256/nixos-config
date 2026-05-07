{
  config,
  lib,
  pkgs,
  ...
}: {
  options.caprine.enable = lib.mkEnableOption "Caprine Facebook Messenger";

  config = lib.mkIf config.caprine.enable {
    home.packages = with pkgs; [caprine];

    systemd.user.services.caprine-autostart = {
      Unit = {
        Description = "Caprine - Facebook Messenger autostart";
        After = [
          "graphical-session-pre.target"
          "wayland-wm@niri-session.service"
        ];
        PartOf = ["graphical-session.target"];
      };
      Service = {
        Type = "simple";
        ExecStart = lib.getExe' pkgs.caprine "caprine";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  };
}
