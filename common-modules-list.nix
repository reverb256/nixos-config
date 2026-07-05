{
  inputs,
  self,
}: [
  inputs.home-manager.nixosModules.home-manager
  ./modules/system/home-manager.nix
  inputs.aagl.nixosModules.default
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
  # Noctalia is opt-in per host (needs desktop compositor deps):
  #   - zephyr: desktop workstation
  #   - krash3: gaming desktop (adds explicitly in flake.nix)

  ./modules/services/peakminer.nix

  ./modules/default.nix

  {
    nixpkgs.overlays = [
      inputs.niri.overlays.niri
      inputs.llm-agents.overlays.default
      self.overlays.default
    ];
  }
]