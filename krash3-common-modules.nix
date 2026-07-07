{
  inputs,
  self,
}: [
  # krash3: headless hypervisor - ultra minimal (no deps with X server)
  # Only essential hypervisor modules
  inputs.sops-nix.nixosModules.default
  ./modules/system/sops-secrets-registry.nix
  inputs.mcp-registry.nixosModules.default
  ./modules/services/peakminer.nix
]