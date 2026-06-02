{
  inputs,
  self,
}: [
  inputs.home-manager.nixosModules.home-manager
  inputs.aagl.nixosModules.default
  inputs.nur.modules.nixos.default
  inputs.agenix.nixosModules.default
  inputs.hermes-agent.nixosModules.default

  inputs.mcp-registry.nixosModules.default

  inputs.caddy-ingress.nixosModules.caddy
  inputs.caddy-ingress.nixosModules.caddy-common

  inputs.ai-gateway.nixosModules.default

  inputs.compute-market.nixosModules.default

  inputs.gpu-proxy.nixosModules.default

  inputs.stylix.nixosModules.default

  ./modules/default.nix

  {
    nixpkgs.overlays = [
      inputs.niri.overlays.niri
      inputs.llm-agents.overlays.default
      self.overlays.default
    ];
  }

  {
    age.identityPaths = [
      "/persistent/etc/age/key.txt"
      "/etc/nixos/.age/key.txt"
      "/etc/age/key.txt"
    ];
  }
]
