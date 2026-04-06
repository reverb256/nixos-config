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
    # Use NixOS's built-in getty autologin for all VTs. The per-compositor
    # selection is handled by the bash-profile.d hook below.
    services.getty = {
      autologinUser = user;
      autologinOnce = false;
      extraArgs = [ "--noclear" ];
    };

    # ── UWSM AUTO-START PER VT ────────────────────────────────────────
    # Primary session (tty1 Plasma) uses UWSM for proper systemd integration.
    # Secondary compositors run directly without --session to avoid messing
    # up the global systemd user environment (graphical-session.target
    # is already owned by the primary Plasma session).
    #
    # Uses programs.fish.loginShellInit because the user's default shell
    # is fish, which doesn't source /etc/profile or /etc/profile.local.
    programs.fish.loginShellInit =
      lib.concatStringsSep "\n" (
        map (s: ''
          if test (tty) = "/dev/${s.tty}"
            set -x XDG_RUNTIME_DIR /run/user/(id -u)
            set -x DBUS_SESSION_BUS_ADDRESS unix:path=$XDG_RUNTIME_DIR/bus
            ${
              if s.name == "plasma" then
                ''
                  set -x UWSM_DESKTOP_NAME "${s.name}"
                  exec uwsm start ${s.desktop}
                ''
              else if s.name == "niri" then
                ''
                  exec niri
                ''
              else
                ''
                  exec Hyprland
                ''
            }
          end
        '') sessions
      )
      + ''

        # If somehow we land here without a matching TTY, start Plasma as default
        if not uwsm check is-active 2>/dev/null
          set -x XDG_RUNTIME_DIR /run/user/(id -u)
          set -x DBUS_SESSION_BUS_ADDRESS unix:path=$XDG_RUNTIME_DIR/bus
          exec uwsm start default
        end
      '';

    # ── VT SWITCH ALIASES ─────────────────────────────────────────────
    programs.fish.shellAliases = {
      plasma = "chvt 1";
      niri = "chvt 2";
      hyprland = "chvt 3";
    };
  };
}
