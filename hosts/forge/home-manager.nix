# Forge Home-Manager Configuration
# GPU computing, mining
{
  config,
  lib,
  pkgs,
  ...
}: {
  home-manager.users.j_kro = {pkgs, ...}: {
    # Mining tools configuration
    home.packages = with pkgs; [
      # GPU monitoring
      nvtopPackages.full
      gpustat

      # Mining tools (if not system-wide)
      lolMiner
      t-rex
    ];

    # GPU monitoring
    home.file.".config/nvtop.conf".source = ../../mining/nvtop.conf;

    # Mining pool configurations
    xdg.configFile."mining/pools.json".source = ../../mining/pools.json;

    # Simple setup - mining is mostly system-wide
  };
}
