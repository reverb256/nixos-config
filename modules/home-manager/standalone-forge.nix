{ pkgs, lib, ... }:
let
  # Resilient package inclusion: return `[pkg]` only if `name` exists in pkgs
  # AND evaluates to a derivation WITHOUT throwing. `tryEval` guards against
  # packages that refuse evaluation in the active nixpkgs (e.g. t-rex, which is
  # marked broken). When a package becomes evaluable, it is picked up
  # automatically on the next build — no manual re-enable needed.
  safePkg = name:
    if builtins.hasAttr name pkgs
    then
      let r = builtins.tryEval pkgs.${name};
      in if r.success
           && builtins.isAttrs r.value
           && r.value ? type
           && r.value.type == "derivation"
         then [ r.value ]
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
