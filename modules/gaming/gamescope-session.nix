{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.gaming.gamescopeSession;
  gamingCfg = config.services.gaming;
  gamescopeCfg = config.programs.gamescope;
in {
  options.services.gaming.gamescopeSession = {
    enable = mkEnableOption "Gamescope Session — Steam Big Picture as an SDDM session (Steam Deck-like experience)";

    steamDeckMode = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Steam Deck UI mode (-gamepadui -steamdeck flags)";
    };

    extraSteamArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional arguments passed to Steam for the session";
    };

    vkDeviceFilter = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "10de:2204";
      description = "PCI vendor:device ID for VK_LOADER_DEVICE_ID_FILTER (dual-GPU safety net)";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = gamingCfg.enable;
        message = "services.gaming.gamescopeSession requires services.gaming.enable";
      }
      {
        assertion = gamescopeCfg.enable;
        message = "services.gaming.gamescopeSession requires programs.gamescope.enable";
      }
    ];

    programs.steam.gamescopeSession = {
      enable = true;

      # Inherit args from programs.gamescope (HDR, NVIDIA device, --backend sdl, etc.)
      args = gamescopeCfg.args;

      # Inherit env from programs.gamescope + dual-GPU Vulkan device filter
      env =
        gamescopeCfg.env
        // optionalAttrs (cfg.vkDeviceFilter != null) {
          VK_LOADER_DEVICE_ID_FILTER = cfg.vkDeviceFilter;
        };

      steamArgs =
        ["-tenfoot" "-pipewire-dmabuf"]
        ++ optionals cfg.steamDeckMode ["-gamepadui" "-steamdeck"]
        ++ cfg.extraSteamArgs;
    };
  };
}
