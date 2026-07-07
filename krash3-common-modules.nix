{
  inputs,
  self,
}: [
  # No home-manager for krash3 (headless hypervisor)
  # inputs.home-manager.nixosModules.home-manager
  # ./modules/system/home-manager.nix

  inputs.aagl.nixosModules.default
  inputs.nur.modules.nixosModules.default
  inputs.sops-nix.nixosModules.default
  ./modules/system/sops-secrets-registry.nix
  inputs.hermes-agent.nixosModules.default
  inputs.mcp-registry.nixosModules.default
  inputs.caddy-ingress.nixosModules.caddy
  inputs.caddy-ingress.nixosModules.caddy-common
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