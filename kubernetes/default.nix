{
  pkgs,
  pkgsWithOverlay,
  inputs,
}:
let
  easykubenix = import inputs.easykubenix {
    inherit pkgs;
    modules = [
      { _module.args.pkgsWithOverlay = pkgsWithOverlay; }
      ./modules/common.nix
      ./modules/infrastructure.nix
      ./modules/ingress.nix
      ./modules/mining.nix
      ./modules/gpu-miners.nix
      ./modules/ai-inference.nix
      ./modules/llama-servers.nix
      ./modules/nixkube.nix
      ./modules/searxng.nix
      ./modules/haven.nix
      ./modules/monitoring.nix
      ./modules/monitoring-dashboards.nix
    ];
  };
in
easykubenix
