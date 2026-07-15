{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  niriEnabled = config.programs.niri.enable or false;
  inherit
    (lib)
    mkForce
    mkIf
    mkMerge
    mkOption
    types
    mkDefault
    ;
in {
  options.desktop.niri = {
    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional packages to install alongside niri";
    };
  };
  config = mkMerge [
    {programs.niri.enable = lib.mkOptionDefault false;}
    (mkIf niriEnabled {
      # Use nixpkgs niri instead of sodiboo/flake niri-unstable.
      # sodiboo/niri-flake ships an HDR-SDR brightness patch that no longer applies
      # against current niri-unstable (MaxBpc removed in niri 26.4).
      # nixpkgs niri is maintained, tracks stable, and avoids the broken patch.
      # Revert to inputs.niri (sodiboo) when their HDR patch is fixed upstream.
      programs.niri.package =
        lib.mkForce
        pkgs.niri;
    })
    (mkIf niriEnabled (
      lib.mkMerge [
        {
          # 2026-07-03: binPath now points at the raw `niri` binary rather than
          # the `niri-session` wrapper. nixpkgs-26.04's wrapper activates
          # systemd targets inside uwsm's wayland-compositor@.service, causing
          # the session to time out after ~42 s and uwsm to exit 64
          # (sddm-helper propagates, repeating the greeter loop).
          # UWSM is designed to drive the compositor directly; the wrapper is
          # redundant under uwsm and conflicts with its session supervision.
          programs.uwsm = {
            enable = lib.mkDefault true;
            waylandCompositors.niri = {
              prettyName = "Niri";
              comment = "A scrollable-tiling Wayland compositor";
              binPath = "/run/current-system/sw/bin/niri";
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
        {
          xdg.portal = {
            enable = mkDefault true;
            # Bypass the portal for xdg-open — flatpak apps call the portal
            # directly via D-Bus regardless, so this only affects native apps.
            # Without this, the portal's built-in OpenURI handler shows an
            # "Open With…" dialog instead of launching the default browser.
            xdgOpenUsePortal = mkForce false;
            config = {
              common.default = "*";
              niri = {
                default = [
                  "gnome"
                  "gtk"
                ];
                "org.freedesktop.impl.portal.Access" = "gtk";
                "org.freedesktop.impl.portal.FileChooser" = "gtk";
                "org.freedesktop.impl.portal.Notification" = "gtk";
                "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
              };
            };
            extraPortals = mkDefault [
              pkgs.xdg-desktop-portal-gnome
              pkgs.xdg-desktop-portal-gtk
            ];
          };

          # 2026-07-15: gnome-keyring was only referenced by the portal
          # Secret=gnome-keyring routing but never enabled as a service.
          # With no keyring daemon, the Secret portal impl fails to acquire
          # at xdg-desktop-portal startup, which can wedge the whole portal
          # daemon — that's why the file picker never opened/persisted.
          # Enable the daemon so the Secret portal (and thus the portal
          # service overall) actually starts.
          services.gnome.gnome-keyring.enable = true;
        }
        {
          environment.systemPackages = with pkgs.kdePackages;
            [
              dolphin
              dolphin-plugins
              konsole # Provides konsolepart plugin for Dolphin terminal
              ark
            ]
            ++ [
              pkgs.swaylock
              pkgs.swayidle
              pkgs.polkit_gnome
              pkgs.xwayland-satellite
            ]
            ++ config.desktop.niri.extraPackages;
        }
        {
          environment.sessionVariables = {
            BROWSER = mkDefault "zen-twilight";
            ELECTRON_OZONE_PLATFORM_HINT = mkDefault "auto";
            NIXOS_OZONE_WL = mkDefault "1";
            MOZ_LEGACY_PROFILES = mkDefault "0";
            MOZ_ENABLE_WAYLAND = mkDefault "1";
            QT_QPA_PLATFORM = mkDefault "wayland;xcb";
            QT_AUTO_SCREEN_SCALE_FACTOR = mkDefault "1";
          };
        }
        {
          environment.etc."uwsm/env-niri" = {
            text = ''
              export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
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
        {
          # Prevent nixos-rebuild from restarting the compositor mid-session.
          # When the niri package changes, systemd --user detects changed unit files
          # and restarts them. For a Wayland compositor, this kills the entire graphical
          # session (niri -> graphical-session.target -> all apps).
          # X-RestartIfChanged=no tells systemd to reload the unit definition but
          # NOT restart the running instance. The new version takes effect on next login.
          # NOTE: environment.etc drop-ins disabled due to Nix sandbox permission issues
          # TODO: Re-enable when NixOS fixed the systemd user drop-in creation
        }
        {
          systemd.user.services = {
            xdg-desktop-portal = {
              after = ["xdg-desktop-autostart.target"];
            };
            xdg-desktop-portal-gnome = {
              after = ["xdg-desktop-autostart.target"];
            };
            xdg-desktop-portal-gtk = {
              after = ["xdg-desktop-autostart.target"];
            };
            niri-idle = lib.mkIf false {
              description = "Idle management for Niri (swayidle)";
              wantedBy = ["graphical-session.target"];
              after = ["graphical-session.target"];
              requisite = ["graphical-session.target"];
              partOf = ["graphical-session.target"];
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
