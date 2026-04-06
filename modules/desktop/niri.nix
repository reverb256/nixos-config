# Niri Module - Companion configuration for sodiboo/niri-flake
# The flake provides programs.niri.enable, programs.niri.settings, etc.
# This module adds: portal backend, NVIDIA support, systemd services
#
# Usage: programs.niri.enable = true; (from niri-flake)
#        This module activates automatically when programs.niri does.
# Shared packages (noctalia-shell, cliphist, etc.) live in wayland-compositor-common.nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  niriEnabled = config.programs.niri.enable or false;
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    types
    mkDefault
    ;
in
{
  options.desktop.niri = {
    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional packages to install alongside niri";
    };
  };

  config = mkMerge [
    # Default: niri available but not active
    { programs.niri.enable = lib.mkOptionDefault false; }

    # Companion config only when niri is ACTUALLY ENABLED
    (mkIf niriEnabled (
      lib.mkMerge [

        # ── BINARY CACHES ──────────────────────────────────────────────

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

        # ── XDG DESKTOP PORTAL ─────────────────────────────────────────
        # Route portal requests to correct backend when Niri is running.
        # xdg.portal.config.<desktop> only applies when XDG_CURRENT_DESKTOP
        # matches, so this doesn't interfere with Plasma or Hyprland sessions.

        {
          xdg.portal = {
            enable = mkDefault true;
            # Niri-specific portal routing (only active in Niri session)
            config.niri = {
              default = [
                "gnome"
                "gtk"
              ];
              "org.freedesktop.impl.portal.Access" = "gtk";
              "org.freedesktop.impl.portal.FileChooser" = "gtk";
              "org.freedesktop.impl.portal.Notification" = "gtk";
              "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
            };
            # gnome portal provides ScreenCast/Screenshot/RemoteDesktop
            # for wlroots compositors without their own portal.
            # Scoped via config.niri above — only used in niri sessions.
            extraPortals = mkDefault [ pkgs.xdg-desktop-portal-gnome ];
          };
        }

        # ── NIRI-ONLY PACKAGES ─────────────────────────────────────────
        # Shared packages (noctalia-shell, cliphist, wf-recorder,
        # adwaita-icon-theme) moved to wayland-compositor-common.nix

        {
          environment.systemPackages = [
            # Screen locker
            pkgs.swaylock
            # Idle management (auto-lock, screen off)
            pkgs.swayidle
            # Polkit authentication agent (niri-specific, not hyprpolkitagent)
            pkgs.polkit_gnome
            # X11 app support (niri uses xwayland-satellite, not xwayland)
            pkgs.xwayland-satellite
          ]
          ++ config.desktop.niri.extraPackages;
        }

        # ── ENVIRONMENT ────────────────────────────────────────────────
        # Global vars: safe defaults identical across all compositors
        # Niri-specific vars: scoped via UWSM env file (no leaks to Plasma/Hyprland)

        {
          environment.sessionVariables = {
            ELECTRON_OZONE_PLATFORM_HINT = mkDefault "auto";
            NIXOS_OZONE_WL = mkDefault "1";
            MOZ_ENABLE_WAYLAND = mkDefault "1";
            QT_QPA_PLATFORM = mkDefault "wayland;xcb";
            QT_AUTO_SCREEN_SCALE_FACTOR = mkDefault "1";
          };
        }

        # ── NVIDIA + NIRI-SCOPED ENV (UWSM) ───────────────────────────
        # DesktopNames=niri → uwsm sources /etc/uwsm/env-niri
        # MUST NOT leak to Plasma (KWin handles its own GPU routing)

        {
          environment.etc."uwsm/env-niri" = {
            text = ''
              # Niri-specific: disable client-side decorations (Niri draws its own)
              export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
            '';
          };
        }

        # ── SYSTEMD USER SERVICES ──────────────────────────────────────
        # Pattern from UWSM example-units/waybar.service:
        #   - WantedBy=graphical-session.target (standard session target)
        #   - ExecCondition filters by XDG_CURRENT_DESKTOP to scope per-compositor
        #   - After=graphical-session.target for proper ordering
        # This avoids hardcoding systemd unit template names like
        #   wayland-session@niri.desktop.target
        # which change if the desktop entry ID changes.

        {
          systemd.user.services = {
            polkit-gnome-authentication-agent-1 = {
              description = "Polkit Authentication Agent (Niri)";
              wantedBy = [ "graphical-session.target" ];
              after = [ "graphical-session.target" ];
              serviceConfig = {
                Type = "simple";
                # Only start when XDG_CURRENT_DESKTOP contains "niri"
                ExecCondition = "${pkgs.systemd}/lib/systemd/systemd-xdg-autostart-condition niri ''";
                ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
                Restart = "on-failure";
                Slice = "session-graphical.slice";
              };
            };
          };
        }
      ]
    ))
  ];
}
