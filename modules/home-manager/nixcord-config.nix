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
        # Declarative seed for Vesktop settings. nixcord hardcodes the
        # generated settings.json as a READ-ONLY symlink into /nix/store
        # (modules/lib/files.nix: mkSettingsSpecs forces writable=false and
        # no per-client option can flip it). Vesktop rewrites settings.json
        # on every UI change, so the ro symlink caused EROFS crashes. The
        # home.activation entry below materializes a real writable copy
        # seeded from nixcord's template after each switch, so the in-app
        # Settings UI can mutate it freely. These values are only the
        # *initial* seed; edit in-app afterwards.
        settings = {
          tray = true;
          minimizeToTray = true;
        };
      };

      config = {
        useQuickCss = true;
        plugins = {
          # Existing plugins
          xsOverlay = {
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
          usrbg = {
            enable = true;
            nitroFirst = true;
            voiceBackground = true;
          };
          reviewDb = {
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
          clearUrls = {
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

    # Materialize a writable Vesktop settings.json. nixcord links
    # ~/.config/vesktop/settings/settings.json into /nix/store (read-only);
    # Vesktop rewrites it on every UI change, so the ro symlink caused EROFS
    # crashes. This resolves the nixcord symlink to its store seed and replaces
    # the symlink with a real writable file seeded from it. Idempotent: if the
    # target is already a regular file (user-mutated), it is left untouched.
    home.activation.vesktopWritableSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
      dest="$HOME/.config/vesktop/settings/settings.json"
      if [ -L "$dest" ]; then
        # resolve the nixcord symlink to its store seed
        seed="$(${lib.getExe' pkgs.coreutils "readlink"} -f "$dest")"
        # remove the symlink (not the store file) and write a real copy
        rm -f "$dest"
        ${lib.getExe' pkgs.coreutils "install"} -Dm644 "$seed" "$dest"
      elif [ ! -e "$dest" ]; then
        # no settings file at all; Vesktop will create its own writable one
        :
      fi
    '';
  };
}
