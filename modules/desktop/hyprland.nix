# Hyprland Module
# Wayland compositor with Noctalia shell ecosystem
#
# Shared packages (noctalia-shell, cliphist, wf-recorder, adwaita-icon-theme)
# moved to wayland-compositor-common.nix to avoid duplication with niri.nix
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.programs.hyprland.enable;
in
{
  config = {
    programs.hyprland = {
      enable = lib.mkDefault false;
      # UWSM provides: session management, auto-restart on crash, proper env setup
      withUWSM = true;
    };

    # Only install ecosystem packages when Hyprland is enabled
    programs.hyprlock.enable = cfg;

    environment.systemPackages = lib.mkIf cfg (
      with pkgs;
      [
        # Core Hyprland tools
        hyprpicker # Color picker
        hyprcursor # Custom cursor support
        hyprlock # Screen locker
        hyprsunset # Blue light filter
        hyprpolkitagent # Polkit agent for Hyprland

        # Wayland utilities
        wayvnc # VNC server for Wayland
      ]
    );

    # ── HYPRLAND-SCOPED ENV (UWSM) ────────────────────────────────────
    # DesktopNames=Hyprland → uwsm sources /etc/uwsm/env-hyprland
    # MUST NOT leak to Plasma (KWin handles its own GPU routing)

    environment.etc."uwsm/env-hyprland" = lib.mkIf cfg {
      text = ''
        # Restrict wlroots to the 3090 (card2) which has all monitors.
        # Prevents DRM master conflicts with card1 (3060 Ti, no displays)
        # when VT switching between compositors.
        WLR_DRM_DEVICES=/dev/dri/card2
      '';
    };

    # ── SYSTEMD USER SERVICES ──────────────────────────────────────────
    # hyprpolkitagent ships its own systemd user service with
    #   WantedBy=graphical-session.target
    #   ConditionEnvironment=WAYLAND_DISPLAY
    # But that would start in ANY Wayland session (Niri, Plasma).
    # We override to add ExecCondition that filters by XDG_CURRENT_DESKTOP,
    # using the UWSM pattern from example-units/waybar.service.
    # The service file is installed by the package, we just need to enable it.

    systemd.user.services = lib.mkIf cfg {
      hyprpolkitagent = {
        # Override upstream service to scope to Hyprland session only
        overrideStrategy = "asDropin";
        serviceConfig = {
          # Only start when XDG_CURRENT_DESKTOP contains "Hyprland"
          # (overrides upstream ConditionEnvironment=WAYLAND_DISPLAY which is too broad)
          ExecCondition = "${pkgs.systemd}/lib/systemd/systemd-xdg-autostart-condition Hyprland ''";
        };
        # Enable the service (upstream ships it but doesn't enable by default)
        enable = true;
      };
    };
  };
}
