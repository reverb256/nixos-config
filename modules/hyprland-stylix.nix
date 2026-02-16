# Stylix Integration for Hyprland
#
# This module extends the Hyprland module with Stylix theming support.
# It updates the hyprland.conf file to use Stylix colors (Base24 if available).

{ pkgs, config, lib, ... }:
{
  imports = [ ./hyprland.nix ];

  options = {
    hyprland = {
      stylixIntegration = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable Stylix color integration for Hyprland theming.

          When enabled, the Hyprland configuration will be automatically
          updated to use colors from the configured Stylix theme
          (Base16 or Base24).
        '';
      };
    };
  };

  config = lib.mkIf config.hyprland.stylixIntegration (lib.mkMerge [
    {
      # Generate Hyprland config file with Stylix colors
      # Colors are derived from config.stylix.base24 or config.lib.stylix.colors

      home.file.".config/hyprland/colors.conf" = {
        enable = true;
        text = ''
          # Stylix color definitions
          ${lib.optionalString config.stylix.base24.base10 "background=#${config.stylix.base24.base10}" ""}
          ${lib.optionalString config.stylix.base24.base11 "foreground=#${config.stylix.base24.base11}" ""}
          ${lib.optionalString config.stylix.base24.base12 "red=#${config.stylix.base24.base12}" ""}
          ${lib.optionalString config.stylix.base24.base13 "green=#${config.stylix.base24.base13}" ""}
          ${lib.optionalString config.stylix.base24.base14 "yellow=#${config.stylix.base24.base14}" ""}
          ${lib.optionalString config.stylix.base24.base15 "blue=#${config.stylix.base24.base15}" ""}
          ${lib.optionalString config.stylix.base24.base16 "magenta=#${config.stylix.base24.base16}" ""}
          ${lib.optionalString config.stylix.base24.base17 "cyan=#${config.stylix.base24.base17}" ""}
          ${lib.optionalString config.stylix.base24.base00 "surface=#${config.lib.stylix.colors.base00}" ""}
        '';
      };

      # Alternatively, use a source statement in main hyprland.conf
      # This allows the theme to change dynamically with Stylix
      home.file.".config/hyprland/colors-theme.source".text = ''
        # Stylix color source file
        # Source this in your main hyprland.conf:
        # source = ~/.config/hyprland/colors-theme.source
      '';

      # Also update the main hyprland.conf to include Stylix colors
      home.file.".config/hyprland/99-stylix-theme.conf" = {
        enable = true;
        text = ''
          # Generated from Stylix theming system
          # This config provides color variables used by your main hyprland.conf
          
          # Border colors
          col.active_border=$${lib.optionalString config.stylix.base24.base0F "${lib.optionalString config.stylix.base24.base14 config.stylix.base24.base14}"}
          col.inactive_border=$${lib.optionalString config.stylix.base24.base01 "${lib.optionalString config.stylix.base24.base10 config.stylix.base24.base10}"}
          
          # Decoration/blur colors
          col.bg=$${config.lib.stylix.colors.base00}
          col.red=$${config.lib.stylix.colors.base08}
          col.green=$${config.lib.stylix.colors.base0B}
          col.blue=$${config.lib.stylix.colors.base0D}
          col.yellow=$${config.lib.stylix.colors.base0A}
          col.magenta=$${config.lib.stylix.colors.base0E}
          col.cyan=$${config.lib.stylix.colors.base0C}
          col.white=$${config.lib.stylix.colors.base07}
          
          # Additional bright colors (Base24)
          col.bright_red=$${config.stylix.base24.base10}
          col.bright_green=$${config.stylix.base24.base11}
          col.bright_yellow=$${config.stylix.base24.base12}
          col.bright_blue=$${config.stylix.base24.base13}
          col.bright_magenta=$${config.stylix.base24.base14}
          col.bright_cyan=$${config.stylix.base24.base15}
          col.bright_black=$${config.stylix.base24.base16}
          col.bright_white=$${config.stylix.base24.base17}
        '';
      };

      # Add reload command for easy theme application
      systemd.user.services.hyprland-theme-reload = {
        Unit = {
          Description = "Hyprland theme reload on Stylix change";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScriptBin "hyprland-reload" ''
            #!/run/current-system/sw/bin/bash
            hyprctl reload config && hyprctl kill waybar
          ''}";
        };
      };
    }
  ]);
}
