# Nixcord Configuration (Home Manager)
# Declarative Discord/Vesktop configuration with Vencord plugins
{
  config,
  pkgs,
  inputs,
  ...
}: {
  programs.nixcord = {
    enable = true;
    discord.enable = false;
    vesktop.enable = true;

    # Base Vencord/Vesktop settings (plugins, themes, etc.)
    vesktopConfig = {
      # Disable Vencord-side tray settings (managed in writable ~/.config/vesktop/settings.json)
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

    # Note: Tray settings (minimizeToTray, trayIcon, etc.) are managed in
    # ~/.config/vesktop/settings.json (writable), not here. Only plugins
    # and Vencord settings are managed declaratively via nixcord.
  };

  # Autostart Vesktop on login with X11 backend for tray icon support
  # Note: nixcord manages plugins and settings declaratively - no additional service needed
  systemd.user.services.vesktop-autostart = {
    Unit = {
      Description = "Vesktop autostart";
      After = [
        "graphical-session-pre.target"
        "plasma-plasmashell.service"
      ];
      PartOf = ["graphical-session.target"];
      Wants = ["plasma-plasmashell.service"]; # Ensure plasma tray is ready
    };
    Service = {
      Type = "simple";
      Environment = [
        # Force X11 backend for StatusNotifierItem/tray icon support
        # This is required for KDE Plasma 6 on Wayland
        "XDG_CURRENT_DESKTOP=KDE"
        "ELECTRON_OZONE_PLATFORM_HINT=x11"
      ];
      # Use XWayland for proper tray icon support on Wayland
      # --enable-features=UseOzonePlatform --ozone-platform-hint=x11 enables StatusNotifierItem
      # --start-minimized: tray settings are in ~/.config/vesktop/settings.json (writable)
      ExecStart = "${pkgs.vesktop}/bin/vesktop --enable-speech-dispatcher --enable-features=UseOzonePlatform --ozone-platform-hint=x11 --start-minimized";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
