# Core desktop environment (Niri-only cluster).
#
# Provides the display manager (SDDM), XWayland, PipeWire audio, Bluetooth,
# and the shared session environment used by the niri-uwsm compositor on all
# desktop hosts. KDE Plasma is not used on this cluster; its (previously
# gated) configuration has been removed. Monitor/TV management lives in
# modules/desktop/desktop-monitor.nix.
{ pkgs, lib, config, ... }: {
  services = {
    xserver = {
      enable = lib.mkDefault true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };
    displayManager = {
      sddm.enable = lib.mkDefault true;
      sddm.settings.General.DisplayServer = "wayland";
    };

    pipewire = {
      enable = lib.mkDefault true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
      # wake noctalia v5 audio control. Noctalia daemon calls into wireplumber
      # for `volume-*` / `mic-*` IPC. NixOS default for
      # `services.pipewire.wireplumber.enable` is `true` since 25.11 but the
      # noctalia launch via `uwsm` runs ahead of the pipewire session
      # sometimes (transient unit ordering). Explicit enable + reload-on-
      # resume ordering avoids racy plugin load failures that mute the
      # daemon's audio IPC.
      wireplumber.enable = lib.mkDefault true;

      # 2026-07-12: stop WirePlumber from pinning each app's stream to a
      # saved sink (node.stream.restore-target). A stale pin had routed
      # Spotify into a microphone/webcam device -> silence, while explicit
      # `pw-play --target` still produced sound. With restore-target off,
      # apps always follow the LIVE default sink chosen in the volume
      # applet instead of a dead remembered target. The poisoned cache
      # (~/.local/state/wireplumber/stream-properties) is cleared once at
      # deploy time so existing bad pins are gone immediately.
      # NOTE: this must be installed via top-level environment.etc — see
      # end of module; services.pipewire.wireplumber.extraConfig builds the
      # derivation but nixos-26.05 does not install it into /etc.
      extraConfig = {
        pipewire."99-lowlatency" = {
          "context.properties" = {
            "default.clock.min-quantum" = 1024;
            "default.clock.max-quantum" = 2048;
          };
          "context.modules" = [
            {
              name = "libpipewire-module-rt";
              flags = [
                "ifexists"
                "nofail"
              ];
              args = {
                "nice.level" = -15;
                "rt.prio" = 19;
                "rt.time.soft" = 200000;
                "rt.time.hard" = 200000;
              };
            }
          ];
        };
        pipewire-pulse."99-lowlatency"."pulse.min.quantum" = "1024/48000";
        client."99-lowlatency"."stream.properties"."node.latency" = "1024/48000";
      };
    };

    pulseaudio.enable = false;

    blueman.enable = true;

    upower.enable = true;
  };

  # Fix: blueman-applet has duplicate ExecStart from systemd.packages install
  # + NixOS auto-override. Clear ExecStart explicitly to replace (not add to)
  # the packaged unit.
  systemd.user.services.blueman-applet.serviceConfig.ExecStart =
    lib.mkForce [ "" "${pkgs.blueman}/bin/blueman-applet" ];

  hardware.bluetooth = {
    enable = lib.mkDefault true;
    powerOnBoot = true;
  };

  security = {
    rtkit.enable = true;

    pam.loginLimits = [
      {
        domain = "@audio";
        item = "rtprio";
        type = "-";
        value = "95";
      }
      {
        domain = "@audio";
        item = "nice";
        type = "-";
        value = "-11";
      }
      {
        domain = "@users";
        item = "memlock";
        type = "-";
        value = "unlimited";
      }
    ];
  };

  environment = {
    sessionVariables = {
      ELECTRON_OZONE_PLATFORM_HINT = "auto";

      GTK_USE_PORTAL = "1";

      QT_MEDIA_BACKEND = "pipewire";
      LD_LIBRARY_PATH = lib.mkBefore [ "/run/current-system/sw/lib/pipewire-0.3" ];

      QT_QPA_PLATFORM = lib.mkOptionDefault "wayland;xcb";
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      QT_QPA_GL_VERSION = "2";
    };
  };

  # NOTE (2026-07-12): WirePlumber restore-target fix. nixos-26.05's
  # services.pipewire.wireplumber.extraConfig builds the derivation but does
  # NOT link it into /etc/wireplumber, so the setting never reached
  # WirePlumber. This drop-in lands at
  # /etc/wireplumber/wireplumber.conf.d/99-no-restore-target.conf and is read
  # on every boot — apps stop being pinned to dead sinks (mic/webcam) and
  # always follow the live default the user picks in the volume applet.
  environment.etc."wireplumber/wireplumber.conf.d/99-no-restore-target.conf".text = ''
    wireplumber.settings = {
      node.stream.restore-target = false
    }
  '';
}
