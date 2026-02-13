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
  plasmoidSrc = ../plasmoids/mining-monitor;
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
    # Install plasmoid system-wide so Plasma can discover it
    environment.systemPackages = [
      (pkgs.runCommand "mining-monitor-plasmoid" {} ''
        mkdir -p $out/share/plasma/plasmoids/${plasmoidName}
        cp -r ${plasmoidSrc}/* $out/share/plasma/plasmoids/${plasmoidName}/
      '')
    ];
  };
}
