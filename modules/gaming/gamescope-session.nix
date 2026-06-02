{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.gaming.gamescopeSession;
  gamingCfg = config.services.gaming;
  gamescopeCfg = config.programs.gamescope;

  envVars =
    gamescopeCfg.env
    // optionalAttrs (cfg.vkDeviceFilter != null) {
      VK_LOADER_DEVICE_ID_FILTER = cfg.vkDeviceFilter;
    };

  steamArgs =
    ["-tenfoot" "-pipewire-dmabuf"]
    ++ optionals cfg.steamDeckMode ["-gamepadui" "-steamdeck"]
    ++ cfg.extraSteamArgs;

  # Build the env export lines from the attrset
  envExports = concatStringsSep "\n" (
    mapAttrsToList (n: v: "export ${n}=${v}") envVars
  );

  steam-gamescope = pkgs.writeShellScriptBin "steam-gamescope" ''
    ${envExports}
    gamescope --steam ${toString gamescopeCfg.args} -- steam ${toString steamArgs}
  '';

  # Session desktop file — self-contained derivation
  gamescopeSessionPkg = pkgs.runCommand "gamescope-session" {} ''
    mkdir -p $out/share/wayland-sessions
    cat > $out/share/wayland-sessions/steam.desktop << EOF
    [Desktop Entry]
    Name=Steam (Gamescope)
    Comment=Steam Big Picture in Gamescope — Steam Deck-like experience
    Exec=${steam-gamescope}/bin/steam-gamescope
    Type=Application
    DesktopNames=Gamescope
    EOF
  '';
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

    # Add wrapper script and session file to system packages
    environment.systemPackages = [
      steam-gamescope
      gamescopeSessionPkg
    ];

    # Ensure wayland-sessions directory is linked from the system environment
    environment.pathsToLink = ["/share/wayland-sessions"];
  };
}
