{
  pkgs,
  config,
  lib,
  ...
}: {
  options.nixcord-config.enable = lib.mkEnableOption "Nixcord Vesktop configuration";

  config = lib.mkIf config.nixcord-config.enable {
    programs.nixcord = {
      enable = true;
      discord.enable = false;
      vesktop = {
        enable = true;
        package = pkgs.vesktop;
        settings = {
          minimizeToTray = true;
          tray = true;
          trayIcon = true;
          openHidden = false;
          arRPC = true;
          splashColor = "rgb(220, 220, 223)";
          splashBackground = "rgb(17, 28, 24)";
          autoStartMinimized = false;
          hardwareVideoAcceleration = true;
          hardwareAcceleration = true;
          customTitleBar = false;
          enableSplashScreen = false;
          clickTrayToShowHide = true;
          disableMinSize = true;
          enableTaskbarFlashing = true;
        };
      };

      config = {
        useQuickCss = true;
        plugins = {
          # Existing plugins
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

          # Quality of life
          voiceMessages = {
            enable = true;
          };
          pictureInPicture = {
            enable = true;
          };
          callTimer = {
            enable = true;
          };
          silentTyping = {
            enable = true;
          };
          notificationVolume = {
            enable = true;
            notificationVolume = 0.5;
          };
          readAllNotificationsButton = {
            enable = true;
          };

          # Privacy / security
          ClearURLs = {
            enable = true;
          };
          consoleJanitor = {
            enable = true;
          };
          noDevtoolsWarning = {
            enable = true;
          };
          crashHandler = {
            enable = true;
          };

          # Media / embeds
          fixYoutubeEmbeds = {
            enable = true;
          };
          fixSpotifyEmbeds = {
            enable = true;
          };
          dearrow = {
            enable = true;
          };
          shikiCodeblocks = {
            enable = true;
          };
          imageZoom = {
            enable = true;
            size = 500.0;
            zoom = 1.0;
          };

          # UI improvements
          betterFolders = {
            enable = true;
          };
          memberCount = {
            enable = true;
          };
          roleColorEverywhere = {
            enable = true;
          };
          showTimeoutDuration = {
            enable = true;
          };
          serverListIndicators = {
            enable = true;
          };
          messageLinkEmbeds = {
            enable = true;
          };
          replyTimestamp = {
            enable = true;
          };

          # Game / streaming
          streamerModeOnStream = {
            enable = true;
          };
          gameActivityToggle = {
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
        ExecStart = lib.getExe pkgs.vesktop;
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  };
}
