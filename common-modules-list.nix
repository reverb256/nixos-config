{
  inputs,
  self,
}: [
  inputs.home-manager.nixosModules.home-manager
  ./modules/system/home-manager.nix
  inputs.aagl.nixosModules.default
  ./modules/desktop/aagl.nix
  inputs.nur.modules.nixos.default
  inputs.sops-nix.nixosModules.default
  ./modules/system/sops-secrets-registry.nix
  inputs.hermes-agent.nixosModules.default

  inputs.mcp-registry.nixosModules.default

  inputs.caddy-ingress.nixosModules.caddy
  inputs.caddy-ingress.nixosModules.caddy-common

  inputs.ai-gateway.nixosModules.default
  inputs.compute-market.nixosModules.default
  inputs.gpu-proxy.nixosModules.default

  inputs.stylix.nixosModules.default

  ./modules/services/peakminer.nix

  ./modules/default.nix

  {
    nixpkgs.overlays = [
      inputs.niri.overlays.niri
      inputs.llm-agents.overlays.shared-nixpkgs
      self.overlays.default
    ];
  }
]