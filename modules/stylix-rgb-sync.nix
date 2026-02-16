# Stylix to OpenRGB Color Sync
# Automatically applies Stylix theme colors to RGB hardware on boot and rebuild

{ pkgs, lib, config, ... }:
with lib;
let
  cfg = config.hardware.rgb.stylixSync;
  colors = config.lib.stylix.colors or {
    # Fallback colors if Stylix not yet initialized
    base00 = "171d23";
    base08 = "f7768e";
    base09 = "ff9e64";
    base0A = "e0af68";
    base0B = "9ece6a";
    base0C = "7dcfff";
    base0D = "7aa2f7";
    base0E = "bb9af7";
    base0F = "bb9af7";
  };
  
  # Selectable accent colors from Stylix palette
  accentOptions = {
    red = colors.base08;
    orange = colors.base09;
    yellow = colors.base0A;
    green = colors.base0B;
    cyan = colors.base0C;
    blue = colors.base0D;
    magenta = colors.base0E;  # Default - Tokyo City Dark purple
    white = colors.base05;
  };
  
  # Get the selected accent color hex (without #)
  accentHex = builtins.substring 1 6 (accentOptions.${cfg.accentColor} or colors.base0E);
  
  # Script to apply Stylix colors to OpenRGB devices
  applyStylixRGB = pkgs.writeShellScriptBin "apply-stylix-rgb" ''
    set -e
    
    # Wait for OpenRGB daemon to be ready (up to 30 seconds)
    echo "Waiting for OpenRGB daemon..."
    for i in $(seq 1 30); do
      if ${pkgs.openrgb}/bin/openrgb -l &>/dev/null 2>&1; then
        echo "OpenRGB daemon ready after $i seconds"
        break
      fi
      if [ $i -eq 30 ]; then
        echo "Timeout waiting for OpenRGB daemon"
        exit 1
      fi
      sleep 1
    done
    
    # Give devices a moment to initialize
    sleep 2
    
    # Apply accent color to all devices in static mode
    echo "Applying Stylix accent color (${accentHex}) to all RGB devices..."
    ${pkgs.openrgb}/bin/openrgb -m static -c ${accentHex} -b ${toString cfg.brightness}
    
    echo "Stylix RGB sync complete!"
  '';
  
in {
  options.hardware.rgb.stylixSync = {
    enable = mkEnableOption "Sync Stylix theme colors to OpenRGB hardware";
    
    accentColor = mkOption {
      type = types.enum [ "red" "orange" "yellow" "green" "cyan" "blue" "magenta" "white" ];
      default = "magenta";
      description = ''
        Which Stylix color to use as RGB accent.
        Options: red, orange, yellow, green, cyan, blue, magenta (default), white
      '';
    };
    
    brightness = mkOption {
      type = types.ints.between 0 100;
      default = 100;
      description = "RGB brightness percentage (0-100)";
    };
  };
  
  config = mkIf cfg.enable {
    # Ensure OpenRGB is enabled
    hardware.rgb.openrgb.enable = lib.mkDefault true;
    
    # Run on boot after display manager starts
    systemd.services.stylix-rgb-boot = {
      description = "Apply Stylix colors to RGB hardware on boot";
      wantedBy = [ "multi-user.target" ];
      after = [ "display-manager.service" "openrgb-daemon.service" ];
      wants = [ "openrgb-daemon.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${applyStylixRGB}/bin/apply-stylix-rgb";
        RemainAfterExit = true;
        
        # Relaxed security for device access
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };
    
    # Run on every nixos-rebuild switch
    system.activationScripts.stylix-rgb-sync = {
      deps = [ "etc" ];
      text = ''
        # Only run if OpenRGB daemon is active
        if systemctl is-active --quiet openrgb-daemon.service 2>/dev/null; then
          echo "Applying Stylix colors to RGB hardware..."
          ${applyStylixRGB}/bin/apply-stylix-rgb || true
        fi
      '';
    };
    
    # Expose current accent color for external tools
    environment.etc."stylix/rgb-accent".text = accentHex;
  };
}
