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
      hyperwhisper-package
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
      Exec=${hyperwhisper-package}/bin/hyperwhisper
      Icon=hyperwhisper
      Terminal=false
      Categories=Utility;Audio;
      X-DBUS-ServiceName=dev.hyperwhisper
    '';

    # ==========================================================================
    # GROUPS PERMISSIONS
    # ==========================================================================
    users.groups.input.gid = config.ids.gids.input or 999;
  };
}
