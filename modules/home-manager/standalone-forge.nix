{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nvtopPackages.full
    gpustat
    lolMiner
    t-rex
  ];

  home.file.".config/nvtop.conf".source = ../../mining/nvtop.conf;
  xdg.configFile."mining/pools.json".source = ../../mining/pools.json;
}
