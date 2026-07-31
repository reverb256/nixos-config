{ pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    nvtopPackages.full
    gpustat
    lolMiner
    t-rex
  ];

  # Optional mining-tool config seeds — only applied when the source file exists
  # in the flake tree (pre-existing gap: mining/ dir not committed). Resilient so
  # the standalone HM layer builds regardless.
  home.file.".config/nvtop.conf" = lib.mkIf (builtins.pathExists ../../mining/nvtop.conf) {
    source = ../../mining/nvtop.conf;
  };
  xdg.configFile."mining/pools.json" = lib.mkIf (builtins.pathExists ../../mining/pools.json) {
    source = ../../mining/pools.json;
  };
}
