{
  inputs,
  self,
}: [
  # krash3: headless hypervisor - minimal module set (no desktop)
  inputs.sops-nix.nixosModules.default
  ./modules/system/sops-secrets-registry.nix
  ./modules/network-constants.nix
  ./modules/hardware/nvidia-common.nix
  ./modules/services/k3s-cluster.nix
  ./modules/services/k3s-pod-affinity.nix
  inputs.mcp-registry.nixosModules.default
  ./modules/services/peakminer.nix
]