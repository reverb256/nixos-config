# ScopeBuddy Module - Gamescope wrapper for Wayland desktop gaming
# Integrates with existing gaming.nix configuration
{
  config,
  lib,
  pkgs,
  inputs ? null,
  ...
}:
with lib; let
  cfg = config.programs.scopebuddy;
in {
  options.programs.scopebuddy = {
    enable = mkEnableOption "ScopeBuddy - gamescope wrapper for Wayland desktop gaming";

    autoDetect = {
      resolution = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically detect and set display resolution";
      };

      hdr = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically enable HDR if display has HDR enabled";
      };

      vrr = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically enable adaptive sync if VRR is active";
      };
    };
  };

  config = mkIf cfg.enable {
    # Add ScopeBuddy dependencies
    environment.systemPackages = with pkgs; [
      jq
      wlr-randr
    ];

    # Add shell aliases for convenience
    programs.fish.shellAliases = {
      scb = mkIf (inputs != null && inputs ? scopebuddy)
        "${inputs.scopebuddy.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/scopebuddy";
      scopebuddy = mkIf (inputs != null && inputs ? scopebuddy)
        "${inputs.scopebuddy.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/scopebuddy";
    };

    # Add system-wide environment variables for auto-detection
    environment.sessionVariables =
      {
        SCB_CONFIG_PATH = "/home/j_kro/.config/scopebuddy/scb.conf";
      }
      // optionalAttrs cfg.autoDetect.resolution {
        SCB_AUTO_RES = "1";
      }
      // optionalAttrs cfg.autoDetect.hdr {
        SCB_AUTO_HDR = "1";
      }
      // optionalAttrs cfg.autoDetect.vrr {
        SCB_AUTO_VRR = "1";
      };
  };
}
