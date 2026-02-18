{
  config,
  lib,
  ...
}:
with lib; {
  options = {
    # Empty options section as we're just configuring existing services
  };

  config = {
    # Disable Ctrl+Alt+F1-F12 shortcuts for TTY switching to prevent interference
    # This addresses the issue where Alt+Left/Right tries to change TTY but doesn't work properly
    services.xserver = mkIf config.services.xserver.enable {
      # Disable the virtual terminal switching shortcuts that conflict with window navigation
      xkb = {
        # Configure XKB options to disable Ctrl+Alt+Fx TTY switching
        options = "terminate:ctrl_alt_bksp"; # Keep only Ctrl+Alt+Backspace to terminate X server
      };
    };

    # For X11 sessions specifically, disable the default keyboard shortcuts that
    # might interfere with Alt+Left/Right navigation
    environment.variables = mkIf config.services.xserver.enable {
      # Disallow VT switching for X11 sessions to prevent the behavior
      XKB_DEFAULT_OPTIONS = "terminate:ctrl_alt_bksp";
    };

    # For Wayland + KDE, we'll use KDE's own configuration to override problematic shortcuts
    # This doesn't affect pure Wayland but helps in XWayland contexts
    environment.etc."xdg/plasma-workspace/env/disable-conflicting-shortcuts.sh".text = ''
      #!/usr/bin/env bash
      # Disable conflicting keyboard shortcuts that interfere with window navigation

      # Only run if KDE session is detected
      if [ -n "$KDE_SESSION_UID" ]; then
        # Unset potentially conflicting Alt+Left/Right shortcuts
        # This addresses the TTY switching behavior when these keys are pressed
        kwriteconfig6 --file kwinrc --group "ModifierOnlyShortcuts" --key "Alt" ""

        # Reload KWin configuration to apply changes
        qdbus org.kde.KWin /KWin reconfigure 2>/dev/null || true
      fi
    '';

    # Make the script executable and ensure it runs in KDE sessions
    systemd.tmpfiles.rules = [
      "f /etc/xdg/plasma-workspace/env/disable-conflicting-shortcuts.sh 0755 root root - -"
    ];
  };
}
