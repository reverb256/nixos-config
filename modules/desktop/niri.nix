# Niri Module - Companion configuration for sodiboo/niri-flake
# The flake provides programs.niri.enable, programs.niri.settings, etc.
# This module adds: portal backend, companion tools, NVIDIA support, systemd services
#
# Usage: programs.niri.enable = true; (from niri-flake)
#        This module activates automatically when programs.niri is enabled.
# Coexists with Plasma 6 - choose "Niri" or "Plasma" in SDDM.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Check if niri is enabled (provided by sodiboo/niri-flake NixOS module)
  niriEnabled = config.programs.niri.enable or false;
  inherit (lib) mkIf mkMerge mkOption types mkDefault;
in {
  # ==========================================================================
  # OPTIONS - Extra configuration for niri setup
  # ==========================================================================
  options.desktop.niri = {
    companionTools = mkOption {
      type = types.bool;
      default = true;
      description = "Install companion tools (waybar, fuzzel, mako, swaylock, swayidle)";
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional packages to install alongside niri";
    };
  };

  # ==========================================================================
  # CONFIG - Activated when programs.niri.enable = true
  # ==========================================================================
  config = mkMerge [
    # Enable niri on all hosts by default (can be overridden per-host)
    {programs.niri.enable = mkDefault true;}

    # Companion config only when niri is actually enabled
    (mkIf niriEnabled (lib.mkMerge [
    # ==========================================================================
    # BINARY CACHE - Avoid building niri from source
    # ==========================================================================
    {
      nix.settings = {
        substituters = mkDefault ["https://niri.cachix.org"];
        trusted-public-keys = mkDefault [
          "niri.cachix.org-1:Wv0O6Tz6V5fM6gD8hIRwM+QjRtBu5OD5QyQjx2hE8vE="
        ];
      };
    }

    # ==========================================================================
    # XDG DESKTOP PORTAL - Per-compositor backend isolation
    # ==========================================================================
    # Plasma uses xdg-desktop-portal-kde (already in plasma6.nix)
    # Niri uses xdg-desktop-portal-gnome for screencasting support
    # xdg-desktop-portal routes based on XDG_CURRENT_DESKTOP at login
    # ==========================================================================
    {
      xdg.portal = {
        enable = mkDefault true;

        # Niri-specific portal routing
        config.niri = {
          default = ["gnome" "gtk"];
          "org.freedesktop.impl.portal.Access" = "gtk";
          "org.freedesktop.impl.portal.FileChooser" = "gtk";
          "org.freedesktop.impl.portal.Notification" = "gtk";
          "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
        };

        # Add gnome portal backend (screencasting support for niri)
        extraPortals = mkDefault [pkgs.xdg-desktop-portal-gnome];
      };

      services.gnome.gnome-keyring.enable = mkDefault true;

      # Prevent gcr-ssh-agent from conflicting with programs.ssh.startAgent
      services.gnome.gcr-ssh-agent.enable = mkDefault false;
    }

    # ==========================================================================
    # COMPANION TOOLS - Replaces what Plasma provides out-of-box
    # ==========================================================================
    (mkIf config.desktop.niri.companionTools {
      environment.systemPackages = [
        # Status bar (replaces Plasma panel)
        pkgs.waybar

        # Application launcher (replaces KRunner)
        pkgs.fuzzel

        # Notification daemon (replaces Plasma notifications)
        pkgs.mako

        # Screen locker (replaces KScreenLocker)
        pkgs.swaylock

        # Idle management (auto-lock, screen off)
        pkgs.swayidle

        # Polkit authentication agent (replaces PolkitKdeAgent)
        pkgs.polkit_gnome

        # Wallpaper
        pkgs.swww

        # GTK theme integration (replaces kde-gtk-config)
        pkgs.nwg-look

        # Brightness control
        pkgs.brightnessctl

        # Screen recording
        pkgs.wf-recorder

        # Clipboard manager
        pkgs.cliphist
      ] ++ config.desktop.niri.extraPackages;
    })

    # ==========================================================================
    # ENVIRONMENT - Wayland/Qt compat (session-scoped, no Plasma conflict)
    # ==========================================================================
    {
      environment.sessionVariables = {
        # Electron/Chromium Wayland native
        ELECTRON_OZONE_PLATFORM_HINT = mkDefault "auto";
        NIXOS_OZONE_WL = mkDefault "1";

        # Firefox Wayland
        MOZ_ENABLE_WAYLAND = mkDefault "1";

        # Qt Wayland
        QT_QPA_PLATFORM = mkDefault "wayland;xcb";
        QT_AUTO_SCREEN_SCALE_FACTOR = mkDefault "1";
        QT_WAYLAND_DISABLE_WINDOWDECORATION = mkDefault "1";
      };
    }

    # ==========================================================================
    # NVIDIA - Multi-GPU support (Zephyr: 2x NVIDIA)
    # ==========================================================================
    # These env vars only affect the niri session; Plasma ignores them
    # ==========================================================================
    (lib.mkIf (config.hardware.nvidia.enable or false) {
      environment.sessionVariables = {
        VK_ICD_FILENAMES = mkDefault
          "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
        GBM_BACKEND = mkDefault "nvidia-drm";
        LIBVA_DRIVER_NAME = mkDefault "nvidia";
        __GLX_VENDOR_LIBRARY_NAME = mkDefault "nvidia";
        WLR_NO_HARDWARE_CURSORS = mkDefault "1";
        NVD_BACKEND = mkDefault "direct";
      };
    })

    # ==========================================================================
    # SYSTEMD USER SERVICES - Auto-started in niri session
    # ==========================================================================
    {
      systemd.user.services = {
        # Polkit authentication dialogs
        polkit-gnome-authentication-agent-1 =
          mkIf config.desktop.niri.companionTools
          {
            description = "Polkit Authentication Agent";
            wantedBy = ["niri.service"];
            serviceConfig = {
              Type = "simple";
              ExecStart =
                "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
              Restart = "on-failure";
            };
          };

        # Notification daemon
        mako =
          mkIf config.desktop.niri.companionTools
          {
            description = "Notification Daemon";
            wantedBy = ["niri.service"];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${pkgs.mako}/bin/mako";
              Restart = "on-failure";
            };
          };

        # Status bar
        waybar =
          mkIf config.desktop.niri.companionTools
          {
            description = "Waybar Status Bar";
            wantedBy = ["niri.service"];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${pkgs.waybar}/bin/waybar";
              Restart = "on-failure";
            };
          };
      };
    }
  ]))
  ];
}
