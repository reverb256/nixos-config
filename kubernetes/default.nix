# Kubernetes manifests generated from Nix modules via easykubenix
#
# Structure:
#   kubernetes/
#   ├── default.nix          # Entry point — wires easykubenix + modules
#   └── modules/
#       ├── mining.nix       # Mining namespace (xmrig, lolMiner, GPU miners)
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
      ./modules/common.nix
      ./modules/mining.nix
    ];
  };
in
easykubenix
