# Monitor Configuration Module
#
# This module provides explicit monitor configuration for Hyprland.
# Allows defining monitor names, their positions, resolutions, and refresh rates.

{ config, lib, ... }:
{
  options = {
    monitors = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      description = ''
        List of monitor configurations for Hyprland.
        Each monitor should have the following attributes:

        - name (string): Monitor identifier (e.g., "DP-1", "HDMI-1")
        - enabled (bool, default: true): Whether the monitor is enabled
        - width (int, optional): Display width in pixels
        - height (int, optional): Display height in pixels
        - refreshRate (int, optional): Refresh rate in Hz
        - x (int, optional): X position
        - y (int, optional): Y position
        - scale (float, optional): Display scaling factor
        - transform (int, optional): Display rotation (0=normal, 1=90°, 2=180°, 3=270°)
        - workspace (int, optional): Default workspace for this monitor
        
        Example:
        {
          name = "DP-1";
          enabled = true;
          width = 2560;
          height = 1440;
          refreshRate = 144;
          scale = 1.0;
        }
      '';
    };
  };

  config = lib.mkIf (config.monitors != []) (
    let
      # Generate Hyprland monitor rules from the configuration
      monitorRules = lib.forEach config.monitors (monitor: ''
        monitor=${monitor.name},${toString monitor.enabled}:${toString (monitor.width or 0)}x${toString (monitor.height or 0)}@${toString (monitor.refreshRate or 60)}${lib.optionalString monitor.scale ",scale=${toString monitor.scale}" ""}${lib.optionalString monitor.transform ",transform=${toString monitor.transform}" ""},prefer_auto,1
      '');

      # Generate monitor.conf with explicit settings
      monitorConf = lib.concatStringsSep "\n" monitorRules;

      # Generate workspace rules to bind monitors to workspaces
      workspaceRules = lib.concatStringsSep "\n" (lib.forEach config.monitors (monitor: ''
        workspace=${monitor.name},${toString (monitor.workspace or 1)}@${monitor.name}
      ''));

      # Create autostart script to apply monitor config
      home.file.".config/hyprland/monitors.conf" = {
        enable = true;
        text = monitorConf;
      };

      # Add script to apply monitor configuration on Hyprland start
      systemd.user.services.hyprland-monitors-setup = {
        Unit = {
          Description = "Configure monitors for Hyprland on startup";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${config.home.homeDirectory}/.local/bin/hyprland-apply-monitors";
        };
      };

      # Create script to apply monitors
      home.file.".local/bin/hyprland-apply-monitors" = {
        enable = true;
        executable = true;
        text = ''
          #!/run/current-system/sw/bin/bash
          # Source the monitor configuration
          if [ -f "$HOME/.config/hyprland/monitors.conf" ]; then
            # Apply to Hyprland
            # Note: This requires hyprctl to be running
            hyprctl reload config &
            
            # Give Hyprland time to apply the configuration
            sleep 2
            
            echo "✅ Monitor configuration applied"
          else
            echo "⚠️ No monitor configuration found"
          fi
        '';
      };
    in {}
  );
}
