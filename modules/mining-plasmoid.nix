# Mining Monitor Plasma Plasmoid
# Multi-node GPU/CPU mining monitor for Plasma 6
#
# Installs a custom plasmoid to monitor lolminer (NVIDIA/AMD) and xmrig across all cluster nodes.
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.programs.mining-plasmoid;

  # Plasmoid source files
  plasmoidName = "org.example.miningmonitor";
  plasmoidDir = pkgs.stdenv.mkDerivation {
    name = "mining-monitor-plasmoid";
    src = ./plasmoids/mining-monitor;

    installPhase = ''
      mkdir -p $out
      cp -r * $out/
    '';
  };
in {
  options.programs.mining-plasmoid = {
    enable = lib.mkEnableOption "Mining Monitor Plasma Plasmoid - Multi-node GPU/CPU monitor";

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User to install the plasmoid for";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install plasmoid system-wide via environment.etc
    # Plasma will pick it up from the XDG data directories
    environment.systemPackages = [
      (pkgs.runCommand "mining-monitor-plasmoid" {} ''
        mkdir -p $out/share/plasma/plasmoids/${plasmoidName}
        cp -r ${./plasmoids/mining-monitor}/* $out/share/plasma/plasmoids/${plasmoidName}/
      '')
    ];

    # Ensure the plasmoid is discoverable
    environment.variables = {
      XDG_DATA_DIRS = ["/run/current-system/sw/share"];
    };
  };
}
