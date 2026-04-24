{
  pkgs,
  pkgsWithOverlay,
  inputs,
}:
let
  llama-cpp-turboquant = inputs.llama-turboquant.packages.x86_64-linux.llama-cpp-turboquant;
  easykubenix = import inputs.easykubenix {
    inherit pkgs;
    modules = [
      { _module.args.pkgsWithOverlay = pkgsWithOverlay; }
      { _module.args.llama-cpp-turboquant = llama-cpp-turboquant; }
      { _module.args.inputs = inputs; }
      # ./modules/nix-csi.nix  # TODO: easykubenix bug - triggers readFile on .drv
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
      ./modules/vane.nix
      ./modules/host-services.nix
      ./modules/ai-coding-tools.nix
    ];
  };
in
easykubenix
