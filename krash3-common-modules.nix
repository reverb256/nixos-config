{
  inputs,
  self,
}: [
  # krash3: headless hypervisor - minimal modules only
  inputs.sops-nix.nixosModules.default
  ./modules/system/sops-secrets-registry.nix
  inputs.mcp-registry.nixosModules.default
  ./modules/services/peakminer.nix
]