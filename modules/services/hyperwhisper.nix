{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib; let
  cfg = config.services.hyperwhisper;
  hyperwhisper-package = inputs.hyperwhisper.packages.${pkgs.system}.default;
in {
  # ==========================================================================
  # MODULE OPTIONS
  # ==========================================================================
  options.services.hyperwhisper = with lib; {
    enable =
      lib.mkEnableOption "Enable HyperWhisper (speech-to-text desktop app)"
      // {
        default = false;
        description = "HyperWhisper desktop app with real-time transcription";
        type = lib.types.bool;
      };

    autoType = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-type transcribed text into active window";
      example = true;
    };

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "moonshine-base";
      description = "Default model to use (moonshine-base, whisper-small, whisper-medium, parakeet-v3-int8, etc.)";
      example = "moonshine-base";
    };
  };

  # ==========================================================================
  # CONFIGURATION
  # ==========================================================================
  config = mkIf cfg.enable {
    # ==========================================================================
    # SYSTEM PACKAGES
    # ==========================================================================
    environment.systemPackages = with pkgs; [
      # Wrapper script for hyperwhisper with XWayland backend
      # Note: WebKitGTK's Wayland backend has protocol errors on both Plasma and Hyprland
      # XWayland (X11 backend) provides reliable compatibility across all compositors
      (pkgs.writeShellScriptBin "hyperwhisper" ''
        # Force X11 backend (XWayland) for compatibility
        # WebKitGTK's native Wayland support has protocol issues with modern compositors
        export GDK_BACKEND=x11

        # Enable portal integration for file dialogs, etc.
        export GTK_USE_PORTAL=1

        # Launch hyperwhisper
        exec ${hyperwhisper-package}/bin/hyperwhisper "$@"
      '')
      wtype
      ydotool
    ];

    # ==========================================================================
    # UDEV RULES FOR YDOTOOL
    # ==========================================================================
    services.udev.extraRules = ''
      # Ydotool uinput device
      KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
    '';

    # ==========================================================================
    # SYSTEMD USER SERVICE FOR YDOTOOLD
    # ==========================================================================
    systemd.user.services.ydotoold = {
      description = "YDotoold - ydotool daemon for keyboard input injection";
      wantedBy = ["default.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.ydotool}/bin/ydotoold";
        Restart = "always";
        RestartSec = 5;
      };
    };

    # ==========================================================================
    # PORTAL CONFIGURATION FOR WAYLAND
    # ==========================================================================
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
      # Use GTK portal as fallback, prefer compositor-specific portals
      config = {
        hyprland.default = ["hyprland" "gtk"];
        kde.default = ["kde" "gtk"];
      };
    };

    # ==========================================================================
    # D-BUS SERVICE FOR GLOBAL HOTKEY SUPPORT
    # ==========================================================================
    services.dbus.packages = [hyperwhisper-package];

    # ==========================================================================
    # DESKTOP ENTRY
    # ==========================================================================
    environment.etc."xdg/autostart/hyperwhisper.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=HyperWhisper
      Comment=Real-time speech-to-text transcription
      Exec=hyperwhisper %F
      Icon=hyperwhisper
      Terminal=false
      Categories=Utility;Audio;
      X-DBUS-ServiceName=dev.hyperwhisper
      SingleMainWindow=true
    '';

    # ==========================================================================
    # GROUPS PERMISSIONS
    # ==========================================================================
    users.groups.input.gid = config.ids.gids.input or 999;
  };
}
