{ pkgs, lib, ... }:
let
  # Resilient package inclusion: include `name` from pkgs only if it evaluates
  # without error. Protects the standalone HM layer from packages that are
  # currently broken/unfree/refuse-evaluation in the active nixpkgs (e.g.
  # t-rex-0.15.0-alpha3). When the package becomes evaluable, it is picked up
  # automatically — no manual re-enable needed.
  tryPkg = name:
    let r = builtins.tryEval (builtins.hasAttr name pkgs && pkgs.${name});
    in lib.optional (r.success && r.value != null) r.value;
in {
  home.packages = with pkgs; [
    nvtopPackages.full
    gpustat
  ] ++ tryPkg "lolMiner"
    ++ tryPkg "t-rex";

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
