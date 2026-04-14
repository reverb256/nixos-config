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
  inputs,
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

    # Use patched niri with SDR brightness support (NV_PLANE_DEGAMMA_MULTIPLIER)
    # Applies local patch to niri-flake package via override
    (mkIf niriEnabled {
      programs.niri.package = lib.mkForce (
        inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-unstable.overrideAttrs (old: {
          patches = (old.patches or []) ++ [
            ./patches/niri-hdr-sdr-brightness.patch
          ];
        })
      );
    })

    # Companion config only when niri is ACTUALLY ENABLED
    (mkIf niriEnabled (
      lib.mkMerge [
        # ── UWSM SESSION MANAGEMENT ───────────────────────────────────
        # Uses NixOS programs.uwsm to create a proper uwsm-wrapped desktop entry
        # for SDDM. uwsm sources /etc/uwsm/env-niri before compositor start,
        # manages systemd lifecycle (slices, scopes, clean shutdown), and provides
        # `uwsm app --` for cgroup-isolated app launching.
        #
        # Flow: SDDM → uwsm start → sources env-niri → wayland-wm@niri.service
        #       → niri-session → niri --session → spawn-at-startup
        #       → uwsm finalize → uwsm app -- for each startup app
        #
        # Built-in uwsm plugins (niri.sh, niri_session.sh) handle:
        #   - Appending "niri" to XDG_CURRENT_DESKTOP
        #   - Marking NIRI_SOCKET, XCURSOR_* for finalize export
        #   - Waiting for NIRI_SOCKET before finalizing
        {
          programs.uwsm = {
            enable = true;
            waylandCompositors.niri = {
              prettyName = "Niri";
              comment = "A scrollable-tiling Wayland compositor";
              binPath = "/run/current-system/sw/bin/niri-session";
            };
          };
        }

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

              # GStreamer plugin path for noctalia-shell (video-wallpaper plugin)
              # Without this, fakesink/coreelements are missing → segfault in QMediaPlayer
              export GST_PLUGIN_PATH=${
                lib.concatStringsSep ":" [
                  "${lib.getLib pkgs.gst_all_1.gstreamer}/lib/gstreamer-1.0"
                  "${pkgs.gst_all_1.gst-plugins-base}/lib/gstreamer-1.0"
                  "${pkgs.gst_all_1.gst-plugins-bad}/lib/gstreamer-1.0"
                  "${pkgs.gst_all_1.gst-plugins-good}/lib/gstreamer-1.0"
                ]
              }
            '';
          };


        }

        # ── SYSTEMD USER SERVICE DROP-INS ──────────────────────────────
        # Fix ordering of dbus-activated services that start before niri
        # creates the Wayland socket, causing spawned apps to crash with
        # "no DISPLAY environment variable specified".
        #
        # Ref: sodiboo/niri-flake#509 (open, no upstream fix)
        # The fix: add xdg-desktop-autostart.target to After= for portal
        # backends and polkit, which ensures they only start after niri
        # and uwsm have set up WAYLAND_DISPLAY / DISPLAY.

        {
          systemd.user.services = {
            xdg-desktop-portal = {
              after = [ "xdg-desktop-autostart.target" ];
            };
            xdg-desktop-portal-gnome = {
              after = [ "xdg-desktop-autostart.target" ];
            };
            xdg-desktop-portal-gtk = {
              after = [ "xdg-desktop-autostart.target" ];
            };
            niri-flake-polkit = {
              after = [ "xdg-desktop-autostart.target" ];
            };

            # When running under uwsm, niri runs as wayland-wm@niri.service
            # (not niri.service). The uwsm quirks_niri_session plugin handles
            # XDG_CURRENT_DESKTOP and NIRI_SOCKET export.
            # Keep niri.service ordering fix for standalone (non-uwsm) sessions.

            polkit-gnome-authentication-agent-1 = {
              description = "Polkit Authentication Agent (Niri)";
              wantedBy = [ "graphical-session.target" ];
              after = [ "graphical-session.target" ];
              requisite = [ "graphical-session.target" ];
              partOf = [ "graphical-session.target" ];
              serviceConfig = {
                Type = "simple";
                ExecCondition = "${pkgs.systemd}/lib/systemd/systemd-xdg-autostart-condition niri ''";
                ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
                Restart = "on-failure";
                Slice = "session-graphical.slice";
              };
            };

            # Idle management — DISABLED (Noctalia shell handles idle via its own settings)
            # Re-enable by removing the mkIf false wrapper if Noctalia idle is removed
            niri-idle = lib.mkIf false {
              description = "Idle management for Niri (swayidle)";
              wantedBy = [ "graphical-session.target" ];
              after = [ "graphical-session.target" ];
              requisite = [ "graphical-session.target" ];
              partOf = [ "graphical-session.target" ];
              serviceConfig = {
                Type = "simple";
                ExecCondition = "${pkgs.systemd}/lib/systemd/systemd-xdg-autostart-condition niri ''";
                ExecStart =
                  "${pkgs.swayidle}/bin/swayidle -w"
                  + " timeout 300 '${pkgs.swaylock}/bin/swaylock'"
                  + " timeout 600 'niri msg action power-off-monitors'"
                  + " resume 'niri msg action power-on-monitors'"
                  + " lock '${pkgs.swaylock}/bin/swaylock'"
                  + " before-sleep '${pkgs.swaylock}/bin/swaylock'";
                Restart = "on-failure";
                RestartSec = 5;
                Slice = "session-graphical.slice";
              };
            };
          };
        }
      ]
    ))
  ];
}
