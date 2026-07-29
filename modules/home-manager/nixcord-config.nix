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
        # NOTE 2026-07-28: removed `settings = { ... }` because nixcord
        # symlinks the generated settings.json into ~/.config/vesktop/
        # settings.json, which points into /nix/store (read-only). Vesktop
        # tries to overwrite this file on every UI change, causing EROFS
        # errors. With no settings block, nixcord leaves ~/.config/vesktop
        # alone and Vesktop writes its own settings.json. User can tune
        # via the in-app Settings UI. To re-enable declarative settings,
        # use a wrapper that copies a Nix-managed template into place at
        # session start, then lets Vesktop mutate it freely.
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
        Environment = [
          "XDG_CURRENT_DESKTOP=KDE"
          # Force the NVIDIA VA-API driver instead of leaving libva to
          # autodetect. Electron auto-detected nouveau/iHD; we want nvidia.
          "LIBVA_DRIVER_NAME=nvidia"
          # Keep VA-API enabled even when electron thinks it has no display
          # device for it (typical under Wayland + NVIDIA DRM-KMS).
          "NVD_BACKEND=direct"
          # Ensure the Wayland socket is reachable
          "ELECTRON_OZONE_PLATFORM_HINT=wayland"
        ];
        ExecStart = lib.getExe pkgs.vesktop + " --no-sandbox";
        Restart = "on-failure";
        # 2026-07-28: bumped from 5s to 30s after SEGV loop. niri+wayland
        # can take ~10s to fully bring up the session; instant restarts
        # were causing the SEGV (core-dump status=11) to repeat.
        RestartSec = "30s";
        # Cap restart attempts to avoid tight loops
        StartLimitIntervalSec = "5min";
        StartLimitBurst = 5;
      };
      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  };
}
