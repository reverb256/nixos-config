# Kubernetes manifests generated from Nix modules via easykubenix
#
# Structure:
#   kubernetes/
#   ├── default.nix          # Entry point — wires easykubenix + modules
#   └── modules/
#       ├── mining.nix       # Mining namespace (xmrig CPU miners)
#       ├── gpu-miners.nix   # GPU miners (lolMiner — CSI + swamp7 image)
#       ├── searxng.nix      # SearXNG metasearch engine
#       ├── common.nix       # Cluster-scoped resources (PriorityClasses, etc.)
#       └── ...
#
# Usage:
#   nix build .#k8s-manifests         # Generate YAML
#   nix run .#k8s-validate             # Validate against ephemeral apiserver
#   nix run .#k8s-deploy               # Deploy via kluctl
#
{
  pkgs,
  pkgsWithOverlay,
  inputs,
}:
let
  easykubenix = import inputs.easykubenix {
    inherit pkgs;
    modules = [
      # Make pkgsWithOverlay available to modules that need overlay packages (lolminer, etc.)
      { _module.args.pkgsWithOverlay = pkgsWithOverlay; }
      ./modules/common.nix
      ./modules/infrastructure.nix
      ./modules/ingress.nix
      ./modules/mining.nix
      ./modules/gpu-miners.nix
      ./modules/ai-inference.nix
      ./modules/searxng.nix
      ./modules/spacebot.nix
    ];
  };
in
easykubenix
