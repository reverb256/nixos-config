{
  inputs,
  self,
}: [
  # krash3: headless hypervisor - minimal module set (no desktop)
  inputs.sops-nix.nixosModules.default
  ./modules/system/sops-secrets-registry.nix
  # CRITICAL: SSH must be present for cluster management. This host was
  # previously excluded from the shared module set and openssh silently
  # defaulted to disabled (no sshd.service) — breaking all SSH access on
  # every rebuild. Always import the SSH module for any reachable host.
  ./modules/system/ssh.nix
  ./modules/network-constants.nix
  ./modules/hardware/nvidia-common.nix
  ./modules/services/k3s-cluster.nix
  ./modules/services/k3s-pod-affinity.nix
  inputs.mcp-registry.nixosModules.default
  ./modules/services/peakminer.nix
]