{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aagl = {
      url = "github:ezKEa/aagl-gtk-on-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-native = {
      url = "github:ryoppippi/claude-code-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-xr = {
      url = "github:nix-community/nixpkgs-xr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    scopebuddy = {
      url = "github:OpenGamingCollective/ScopeBuddy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcord = {
      url = "github:FlameFlag/nixcord";
    };
  };

  outputs = { self, nixpkgs, home-manager, zen-browser, firefox-addons, aagl, nur, claude-native, nixpkgs-xr, scopebuddy, nixcord }:
    {
      packages.x86_64-linux.claude = claude-native.packages.x86_64-linux.claude;

      overlays.default = import ./overlay.nix;

      nixosConfigurations.zephyr = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inputs = {
            inherit nixpkgs home-manager zen-browser firefox-addons aagl nur claude-native nixpkgs-xr scopebuddy nixcord self;
          };
        };
        modules = [
          ./hosts/zephyr/configuration.nix
          home-manager.nixosModules.home-manager
          aagl.nixosModules.default
          nur.nixosModules.nur
          {nixpkgs.overlays = [ self.overlays.default ];}
        ];
      };
    };
}
