{
  inputs,
  self,
}:
[


  inputs.home-manager.nixosModules.home-manager
  inputs.aagl.nixosModules.default
  inputs.nur.modules.nixos.default
  inputs.agenix.nixosModules.default
  inputs.nixpkgs-xr.nixosModules.nixpkgs-xr
  inputs.niri.nixosModules.niri
  inputs.hermes-agent.nixosModules.default

  inputs.mcp-registry.nixosModules.default

  inputs.stylix.nixosModules.stylix


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
      "/etc/nixos/.age/key.txt"
      "/etc/age/key.txt"
      "/home/j_kro/.age/key.txt"
    ];
  }
]
