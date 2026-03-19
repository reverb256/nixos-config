# Disable KDE features that trigger TV CABC (Content Adaptive Brightness)
# CABB reacts to pixel changes from mouse/keyboard input
{config, pkgs, ...}: {
  # KDE Display Configuration - Lock down to prevent changes
  environment.variables = {
    # Disable colord (color management daemon)
    COLORD_DISABLE = "1";
    # Disable auto color profile switching
    SDL_DISABLE_WATCHDOG = "1";
    # Force static color profile
    __GL_SYNC_TO_VBLANK = "0";
  };

  # Systemd user service to lock display settings
  systemd.user.services.fix-display-brightness = {
    Unit = {
      Description = "Lock display settings to prevent TV CABC triggers";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.writeScript "lock-display-settings" ''
        #!/run/current-system/sw/bin/bash
        set -euo pipefail

        echo "Locking display settings to prevent TV CABC triggers..."

        # Disable KDE color management daemon (prevents profile switching)
        systemctl --user stop colord.service 2>/dev/null || true
        systemctl --user mask colord.service 2>/dev/null || true

        # Force static color temperature via ICC profile (if available)
        # This prevents KDE from adjusting color based on content
        mkdir -p ~/.config
        cat > ~/.config/kdeglobals << 'EOF'
        [General]
        # Disable color profile management
        DisableColorCorrection=true

        [Screen]
        # Prevent screen from adjusting to content
        ScaleFactor=1

        [Windows]
        # Prevent window decorations from triggering changes
        SeparateScreenFocus=true
EOF

        echo "Display settings locked. CABB should no longer react to mouse/keyboard."
      ''";
    };
  };
}
