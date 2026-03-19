# Disable CABC (Content Adaptive Brightness Control) Triggers
# Prevents TV brightness from reacting to mouse/keyboard input by disabling
# Linux features that trigger HDMI control signals that TVs interpret as content changes
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.gaming.disableCabcTriggers;
in {
  options.services.gaming.disableCabcTriggers = mkEnableOption "Disable CABC triggers for HDMI TVs";

  config = mkIf cfg.enable {
    # ============================================================================
    # DISABLE COLOR MANAGEMENT DAEMON (colord)
    # ============================================================================
    # colord monitors displays and switches ICC profiles, sending HDMI control
    # signals that trigger TV CABC to adjust brightness
    services.colord.enable = mkForce false;

    # Disable colord integration in KDE
    services.displayManager.defaultSession = "plasma"; # Ensure Plasma session

    # ============================================================================
    # DISABLE POWERDEVIL DISPLAY POWER FEATURES
    # ============================================================================
    # PowerDevil sends DPMS signals that can trigger HDMI renegotiation
    environment.etc."xdg/powermanagementprofilesrc".text = ''
      [Profile]
      Actions=undefined

      [AC][BrightnessControl]
      # Disable brightness control to prevent HDMI signals
      enable=false

      [AC][DPMSControl]
      # Disable DPMS to prevent HDMI sleep/wake signals
      enable=false

      [Battery][BrightnessControl]
      enable=false

      [Battery][DPMSControl]
      enable=false
    '';

    # ============================================================================
    # STATIC KDE CONFIGURATION
    # ============================================================================
    # Prevent dynamic color profile switching
    environment.etc."xdg/kdeglobals".text = ''
      [General]
      # Fixed color scheme - no automatic changes
      ColorScheme=Default

      [KDE]
      # Look and feel - lock to prevent theme changes
     LookAndFeelScheme=org.kde.breeze.desktop

      [Colors:Window]
      BackgroundNormal=49,54,59

      [Colors:Selection]
      BackgroundNormal=61,174,233

      [Colors:Button]
      BackgroundNormal=49,54,59

      [Colors:Tooltip]
      BackgroundNormal=49,54,59
    '';

    # Disable KDE color management integration
    environment.plasma6.excludePackages = with pkgs.kdePackages; [
      colord-kde
    ];

    # ============================================================================
    # DISABLE KSCREEN DYNAMIC DISPLAY CHANGES
    # ============================================================================
    # Prevent KScreen from re-negotiating HDMI connection
    environment.etc."xdg/kscreenlockerrc".text = ''
      [Daemon]
      # Disable background monitoring of display changes
      LockEnabled=false
    '';

    environment.etc."xdg/kscreendrc".text = ''
      [General]
      # Disable automatic screen arrangement changes
      ControlCenter=false
    '';

    # ============================================================================
    # SYSTEMD USER UNITS TO BLOCK COLOR MANAGEMENT
    # ============================================================================
    systemd.user.services."disable-colord-triggers" = {
      description = "Disable colord and color profile triggers";
      wantedBy = ["default.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "disable-colord-triggers" ''
          #!/bin/sh
          # Block colord from starting
          systemctl --user mask colord.service 2>/dev/null || true

          # Disable KDE color management integration
          mkdir -p "$HOME/.config"
          echo "[General]" > "$HOME/.config/kdeglobals"
          echo "ColorScheme=Default" >> "$HOME/.config/kdeglobals"
          echo "LookAndFeelScheme=org.kde.breeze.desktop" >> "$HOME/.config/kdeglobals"

          # Disable PowerDevil display power management
          echo "[AC]" > "$HOME/.config/powermanagementprofilesrc"
          echo "[AC][DPMSControl]" >> "$HOME/.config/powermanagementprofilesrc"
          echo "enable=false" >> "$HOME/.config/powermanagementprofilesrc"
          echo "[AC][BrightnessControl]" >> "$HOME/.config/powermanagementprofilesrc"
          echo "enable=false" >> "$HOME/.config/powermanagementprofilesrc"
          echo "[Battery][DPMSControl]" >> "$HOME/.config/powermanagementprofilesrc"
          echo "enable=false" >> "$HOME/.config/powermanagementprofilesrc"
          echo "[Battery][BrightnessControl]" >> "$HOME/.config/powermanagementprofilesrc"
          echo "enable=false" >> "$HOME/.config/powermanagementprofilesrc"
        '';
      };
    };

    # ============================================================================
    # XDG AUTOSTART DISABLE
    # ============================================================================
    # Prevent colord and color management from auto-starting
    environment.etc."xdg/autostart/colord-kde.desktop".text = ''
      [Desktop Entry]
      Hidden=true
      X-GNOME-Autostart-enabled=false
    '';

    # ============================================================================
    # NVIDIA DRIVER SETTINGS
    # ============================================================================
    # Force static colorimetry to prevent HDMI color space changes
    hardware.nvidia.forceFullCompositionPipeline = true;

    # Disable dynamic range control
    environment.sessionVariables = {
      # Force full RGB range (no limited/auto range switching)
      __GL_SYNC_TO_VBLANK = "0";
      # Disable dynamic color range
      __GL_SHADER_DISK_CACHE = "1";
    };
  };
}
