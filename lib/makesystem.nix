# lib/makesystem.nix
{
  self,
  nixpkgs,
  home-manager,
  agenix,
  ezkea,
  determinate,
  nix-gaming,
  ...
} @ inputs: {
  hostname,
  system ? "x86_64-linux",
  extraModules ? [],
  enableHomeManager ? true,  # NEW: Control home-manager inclusion
}:
nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = {inherit inputs;};
  modules =
    [
      # Base configuration
      ./../configuration.nix

      # Overlays
      {
        nixpkgs.overlays = [
          self.overlays.default
        ];
        nixpkgs.config.allowUnfree = true;
        nixpkgs.config.permittedInsecurePackages = [
          "electron-25.9.0"
        ];
      }

      # External modules
      ezkea.nixosModules.default
      determinate.nixosModules.default
      nix-gaming.nixosModules.pipewireLowLatency
      nix-gaming.nixosModules.platformOptimizations

      # Agenix for secrets management
      agenix.nixosModules.default

      # Host-specific configuration
      ./../hosts/${hostname}/configuration.nix
    ]
    ++ extraModules
    # Conditionally add home-manager
    ++ (nixpkgs.lib.optionals enableHomeManager [
      home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.j_kro = import ./../home.nix;
        home-manager.extraSpecialArgs = {inherit inputs;};
      }
    ]);
}
