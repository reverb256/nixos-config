{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.spotify-spicetify;
  stateDir = "/var/lib/spicetify";

in {
  options.services.spotify-spicetify = {
    enable = mkEnableOption "Spotify theming and extensions via Spicetify";

    configPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to custom Spicetify config directory";
    };

    theme = mkOption {
      type = types.nullOr types.str;
      default = "Dribbblish";
      description = "Theme name to apply";
    };

    colorScheme = mkOption {
      type = types.str;
      default = "nord-dark";
      description = "Color scheme for theme";
    };

    customCSS = mkOption {
      type = types.lines;
      default = "";
      description = "Custom CSS to inject";
    };

    extensions = mkOption {
      type = types.listOf types.str;
      default = [ "adblock" "shuffle+" ];
      description = "List of extension names to enable";
    };

    customApps = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of custom apps to add";
    };

    autoApply = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically re-apply when Spotify updates";
    };

    checkInterval = mkOption {
      type = types.str;
      default = "daily";
      description = "How often to check and re-apply";
    };

    onFailure = mkOption {
      type = types.enum [ "disable" "notify-only" "ignore" ];
      default = "disable";
      description = "Behavior when Spicetify fails";
    };

    enableNotifications = mkOption {
      type = types.bool;
      default = true;
      description = "Send desktop notifications";
    };

    preApplyHook = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Script to run before applying";
    };

    postApplyHook = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Script to run after applying";
    };
  };

  config = mkIf cfg.enable {
    # TODO: Add implementation in next tasks
  };
}