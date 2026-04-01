# Niri Module - Companion configuration for sodiboo/niri-flake
# The flake provides programs.niri.enable, programs.niri.settings, etc.
# This module adds: portal backend, Noctalia shell, NVIDIA support, systemd services
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
  niriEnabled = config.programs.niri.enable or false;
  inherit (lib) mkIf mkMerge mkOption types mkDefault;
in {
  options.desktop.niri = {
    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional packages to install alongside niri";
    };
  };

  config = mkMerge [
    # Enable niri on all hosts by default (can be overridden per-host)
    {programs.niri.enable = mkDefault true;}

    # Companion config only when niri is actually enabled
    (mkIf niriEnabled (lib.mkMerge [
      # ========================================================================
      # BINARY CACHES - Avoid building niri and noctalia from source
      # ========================================================================
      {
        nix.settings = {
          substituters = mkDefault [
            "https://niri.cachix.org"
            "https://noctalia.cachix.org"
          ];
          trusted-public-keys = mkDefault [
            "niri.cachix.org-1:Wv0O6Tz6V5fM6gD8hIRwM+QjRtBu5OD5QyQjx2hE8vE="
            "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
          ];
        };
      }

      # ========================================================================
      # XDG DESKTOP PORTAL - Per-compositor backend isolation
      # ========================================================================
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

          extraPortals = mkDefault [pkgs.xdg-desktop-portal-gnome];
        };

        services.gnome.gnome-keyring.enable = mkDefault true;
        services.gnome.gcr-ssh-agent.enable = mkDefault false;
      }

      # ========================================================================
      # COMPANION TOOLS - Noctalia shell + utilities
      # ========================================================================
      # Noctalia-shell replaces: waybar (bar), mako (notifications), fuzzel (launcher)
      # It also handles: wallpapers, dock, session menu, media controls, volume OSD
      # ========================================================================
      {
        environment.systemPackages = [
          # Desktop shell (bar, notifications, launcher, dock, wallpapers)
          pkgs.noctalia-shell

          # Screen locker
          pkgs.swaylock

          # Idle management (auto-lock, screen off)
          pkgs.swayidle

          # Polkit authentication agent
          pkgs.polkit_gnome

          # Screen recording
          pkgs.wf-recorder

          # Clipboard manager (noctalia clipboard integration)
          pkgs.cliphist

          # X11 app support (niri uses xwayland-satellite, not xwayland)
          pkgs.xwayland-satellite

          # Cursor theme (matches xcursor-theme "Adwaita" in niri settings)
          pkgs.adwaita-icon-theme
        ] ++ config.desktop.niri.extraPackages;
      }

      # ========================================================================
      # ENVIRONMENT - Wayland/Qt compat (session-scoped, no Plasma conflict)
      # ========================================================================
      {
        environment.sessionVariables = {
          ELECTRON_OZONE_PLATFORM_HINT = mkDefault "auto";
          NIXOS_OZONE_WL = mkDefault "1";
          MOZ_ENABLE_WAYLAND = mkDefault "1";
          QT_QPA_PLATFORM = mkDefault "wayland;xcb";
          QT_AUTO_SCREEN_SCALE_FACTOR = mkDefault "1";
          QT_WAYLAND_DISABLE_WINDOWDECORATION = mkDefault "1";
        };
      }

      # ========================================================================
      # NVIDIA - Multi-GPU support (Zephyr: 2x NVIDIA)
      # ========================================================================
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

      # ========================================================================
      # SYSTEMD USER SERVICES - Auto-started in niri session
      # ========================================================================
      {
        systemd.user.services = {
          polkit-gnome-authentication-agent-1 = {
            description = "Polkit Authentication Agent";
            wantedBy = ["niri.service"];
            serviceConfig = {
              Type = "simple";
              ExecStart =
                "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
              Restart = "on-failure";
            };
          };
        };
      }
    ]))
  ];
}
