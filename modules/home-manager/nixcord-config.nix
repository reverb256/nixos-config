{
  pkgs,
  config,
  lib,
  ...
}: let
  discord-patched = pkgs.discord.override {
    withOpenASAR = true;
    withVencord = true;
  };
in {
  options.nixcord-config.enable = lib.mkEnableOption "Nixcord Discord configuration";

  config = lib.mkIf config.nixcord-config.enable {
    home.packages = [discord-patched];

    programs.nixcord = {
      enable = true;
      discord.enable = false;
      vesktop.enable = false;

      config = {
        useQuickCss = true;
        plugins = {
          XSOverlay = {
            enable = true;
            dmNotifications = true;
            groupDmNotifications = true;
            serverNotifications = true;
            callNotifications = true;
            channelPingColor = "#8a2be2";
            pingColor = "#7289da";
            timeout = 3;
            volume = 0.2;
            opacity = 1.0;
          };
          fakeNitro = {
            enable = true;
            enableEmojiBypass = true;
            enableStickerBypass = true;
            enableStreamQualityBypass = true;
            emojiSize = 48.0;
          };
          USRBG = {
            enable = true;
            nitroFirst = true;
            voiceBackground = true;
          };
          ReviewDB = {
            enable = true;
          };
        };
      };
    };

    systemd.user.services.discord-autostart = {
      Unit = {
        Description = "Discord autostart";
        After = [
          "graphical-session-pre.target"
          "wayland-wm@niri-session.service"
        ];
        PartOf = ["graphical-session.target"];
      };
      Service = {
        Type = "simple";
        Environment = ["XDG_CURRENT_DESKTOP=KDE"];
        ExecStart = lib.getExe discord-patched + " --start-minimized";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  };
}
