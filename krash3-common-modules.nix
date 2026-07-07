{
  inputs,
  self,
}: [
  # krash3: headless hypervisor - minimal modules only
  inputs.sops-nix.nixosModules.default
  ./modules/system/sops-secrets-registry.nix
  inputs.hermes-agent.nixosModules.default
  inputs.mcp-registry.nixosModules.default
  inputs.ai-gateway.nixosModules.default
  inputs.compute-market.nixosModules.default
  inputs.gpu-proxy.nixosModules.default
  ./modules/services/peakminer.nix
  {
    nixpkgs.overlays = [
      self.overlays.default
    ];
  }
]