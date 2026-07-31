{ pkgs, lib, ... }:
let
  # Resilient package inclusion: return `[pkg]` only if `name` exists in pkgs
  # AND evaluates to a derivation. `hasAttr` is checked first (no throwing
  # access), so missing packages (e.g. vllm-env, lolMiner) don't error. Broken
  # / refuse-evaluation packages are skipped too. When a package becomes
  # available, it is picked up automatically on next build.
  safePkg = name:
    if builtins.hasAttr name pkgs
    then
      let p = pkgs.${name};
      in if builtins.isAttrs p && p ? type && p.type == "derivation"
         then [ p ]
         else []
    else [];
in {
  home.packages = with pkgs; [
    nvtopPackages.full
    gpustat
  ] ++ safePkg "lolMiner"
    ++ safePkg "t-rex";

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
