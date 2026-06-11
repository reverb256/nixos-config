{
  inputs,
  self,
}: [
  inputs.home-manager.nixosModules.home-manager
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

  ./modules/default.nix

  # Disable kmscon from ALL sources — stylix sets deprecated options
  # (extraConfig, fonts) that fail with current nixpkgs. Nobody uses kmscon.
  # Uses "kmscon/nixos.nix" suffix to match both nixpkgs (services/kmscon/...)
  # and stylix (modules/kmscon/...) paths.
  {
    disabledModules = [ "kmscon/nixos.nix" ];
  }

  {
    nixpkgs.overlays = [
      inputs.niri.overlays.niri
      inputs.llm-agents.overlays.default
      self.overlays.default
    ];
  }
]
