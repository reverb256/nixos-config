# UWSM Multi-Compositor Sessions
# Replaces SDDM with per-VT auto-login via systemd getty + UWSM
#
# Layout:
#   tty1 - Plasma 6 (Wayland)    — primary desktop
#   tty2 - Niri (scrollable tiling) — secondary compositor
#   tty3 - Hyprland (UWSM)       — tiling compositor
#
# All managed by UWSM for consistent session handling.
# Switch between sessions with Ctrl+Alt+F1/F2/F3.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.desktop.uwsm-sessions.enable;
  user = "j_kro";

  # Per-VT session definitions
  sessions = [
    {
      tty = "tty1";
      name = "plasma";
      desktop = "plasma.desktop";
    }
    {
      tty = "tty2";
      name = "niri";
      desktop = "niri";
    }
    {
      tty = "tty3";
      name = "hyprland";
      desktop = "hyprland-uwsm.desktop";
    }
  ];
in
{
  options.desktop.uwsm-sessions = {
    enable = lib.mkEnableOption "UWSM multi-compositor sessions (Plasma/Niri/Hyprland on tty1/2/3)";
  };

  config = lib.mkIf cfg {
    # Disable SDDM — UWSM handles session launch directly
    services.xserver.displayManager.sddm.enable = lib.mkForce false;

    # Ensure only Wayland sessions are generated (no X11)
    services.xserver.enable = lib.mkDefault true;
    services.xserver.desktopManager.xterm.enable = lib.mkDefault false;
    services.xserver.windowManager.session = lib.mkForce [ ];

    # Suppress Plasma X11 session — Wayland only
    services.xserver.displayManager.sessionPackages = lib.mkForce [ ];

    # Remove raw hyprland.desktop — only keep hyprland-uwsm.desktop
    # (withUWSM = true generates both; we suppress the raw one)
    environment.etc."uwsm/env-hyprland".text = lib.mkAfter "";

    # Per-VT auto-login via getty
    systemd.services = lib.listToAttrs (
      map (s: {
        name = "getty@${s.tty}";
        value = {
          overrideStrategy = "asDropin";
          serviceConfig = {
            ExecStart = lib.mkForce [
              "/run/current-system/sw/bin/agetty"
              "--autologin"
              user
              "--noclear"
              s.tty
              "linux"
            ];
            Restart = "no";
            Type = "idle";
          };
        };
      }) sessions
    );

    # UWSM auto-start per VT via bash profile
    environment.etc."bash-profile.d/uwsm-sessions".text =
      lib.concatStringsSep "\n" (
        map (s: ''
          if [[ $(tty) == "/dev/${s.tty}" ]]; then
            export UWSM_DESKTOP_NAME="${s.name}"
            exec uwsm start ${s.desktop}
          fi
        '') sessions
      )
      + ''

        # If somehow we land here without a matching TTY, start Plasma as default
        if ! uwsm check is-active 2>/dev/null; then
          exec uwsm start default
        fi
      '';

    # Helper aliases for switching VTs
    environment.etc."bashrc.d/uwsm-aliases".text = ''
      # VT switch aliases
      alias plasma='chvt 1'
      alias niri='chvt 2'
      alias hyprland='chvt 3'
    '';
  };
}
