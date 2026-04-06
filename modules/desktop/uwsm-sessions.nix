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
#
# Per-compositor env files managed by:
#   niri.nix     → /etc/uwsm/env-niri (Qt window decorations)
#   hyprland.nix → /etc/uwsm/env-hyprland (reserved, currently empty)
#   NVIDIA vars  → set globally by nvidia-wayland.nix (all sessions)
#   Plasma       → uses KWin's built-in GPU routing (no env file needed)
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
      desktop = "niri.desktop";
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
    # ── DISABLE SDDM ──────────────────────────────────────────────────
    services.xserver.displayManager.sddm.enable = lib.mkForce false;

    # Ensure only Wayland sessions are generated (no X11)
    services.xserver.enable = lib.mkDefault true;
    services.xserver.desktopManager.xterm.enable = lib.mkDefault false;
    services.xserver.windowManager.session = lib.mkForce [ ];

    # Suppress Plasma X11 session — Wayland only
    services.displayManager.defaultSession = lib.mkForce "plasma";

    # ── PER-VT AUTO-LOGIN ─────────────────────────────────────────────
    systemd.services = lib.listToAttrs (
      map (s: {
        name = "getty@${s.tty}";
        value = {
          # Don't use asDropin — dropins merge with the base unit, keeping
          # the original ExecStart alongside ours (systemd rejects multiple
          # ExecStart= for non-oneshot types). A full replacement overrides it.
          serviceConfig = {
            ExecStart = "${pkgs.util-linux}/bin/agetty --autologin ${user} --noclear ${s.tty} linux";
            Restart = "no";
            Type = "idle";
          };
        };
      }) sessions
    );

    # ── UWSM AUTO-START PER VT ────────────────────────────────────────
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

    # ── VT SWITCH ALIASES ─────────────────────────────────────────────
    environment.etc."bashrc.d/uwsm-aliases".text = ''
      # VT switch aliases
      alias plasma='chvt 1'
      alias niri='chvt 2'
      alias hyprland='chvt 3'
    '';
  };
}
