# lib/common.nix
{
  inputs,
  ...
}: [
  # Common Configuration
  ./../configuration.nix

  # External Modules
  inputs.ezkea.nixosModules.default
  inputs.determinate.nixosModules.default
  inputs.nix-gaming.nixosModules.pipewireLowLatency
  inputs.nix-gaming.nixosModules.platformOptimizations
  inputs.agenix.nixosModules.default

  # Colmena Deployment Options (prevents errors in nixos-rebuild)
  inputs.colmena.nixosModules.deploymentOptions

  # Home Manager
  inputs.home-manager.nixosModules.home-manager
  {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.j_kro = import ./../home.nix;
    home-manager.extraSpecialArgs = {inherit inputs;};
  }
]
