{pkgs, config, lib, ...}: {
  options.nixcord-config.enable = lib.mkEnableOption "Nixcord Vesktop configuration";

  config = lib.mkIf config.nixcord-config.enable {
    programs.nixcord = {
      enable = true;
    discord.enable = false;
    vesktop.enable = true;

    vesktopConfig = {
      tray = false;
      trayIcon = false;
      openHidden = false;

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
          enableStreamBypass = true;
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

  systemd.user.services.vesktop-autostart = {
    Unit = {
      Description = "Vesktop autostart";
      After = [
        "graphical-session-pre.target"
        "wayland-wm@niri-session.service"
      ];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "simple";
      Environment = ["XDG_CURRENT_DESKTOP=KDE"];
      ExecStart = lib.getExe pkgs.vesktop + " --start-minimized";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
  };
}
