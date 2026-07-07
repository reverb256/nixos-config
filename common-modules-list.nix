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

  # Desktop modules (niri, stylix, noctalia)
  # NOTE: krash3 (headless hypervisor) EXCLUDES these in colmena.nix
  # inputs.stylix.nixosModules.default
  # inputs.niri.overlays.niri
  # inputs.llm-agents.overlays.default

  ./modules/services/peakminer.nix

  ./modules/default.nix

  {
    nixpkgs.overlays = [
      # Desktop overlays - krash3 EXCLUDES these
      # inputs.niri.overlays.niri
      # inputs.llm-agents.overlays.default
      self.overlays.default
    ];
  }
]