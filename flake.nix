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
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Colmena - Multi-host deployment
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { self, nixpkgs, home-manager, spicetify-nix, zen-browser, firefox-addons, aagl, nur, claude-native, nixpkgs-xr, scopebuddy, nixcord, agenix, colmena }:
    let
      # ========================================================================
      # COMMON MODULES - Shared across all hosts (single source of truth)
      # ========================================================================
      commonModules = [
        # External modules
        home-manager.nixosModules.home-manager
        aagl.nixosModules.default
        nur.modules.nixos.default
        agenix.nixosModules.default

        # Internal modules (auto-imports all subdirectories)
        ./modules/default.nix

        # Overlays configuration - applies overlays.default to all hosts
        { nixpkgs.overlays = [ self.overlays.default ]; }
      ];

      # ========================================================================
      # HELPER FUNCTION - Create NixOS system (eliminates duplication)
      # ========================================================================
      mkNixosSystem = { hostName, extraModules ? [] }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = commonModules ++ [
            ./hosts/${hostName}/configuration.nix
          ] ++ extraModules;
        };

      # ========================================================================
      # HOST DEFINITIONS - Single source of truth
      # ========================================================================
      hosts = {
        zephyr = { hostName = "zephyr"; };
        nexus = { hostName = "nexus"; };
        forge = { hostName = "forge"; };
        sentry = { hostName = "sentry"; };
      };

    in {
      # ========================================================================
      # OUTPUT 1: nixosConfigurations (for local nixos-rebuild)
      # ========================================================================
      nixosConfigurations = builtins.mapAttrs
        (name: value: mkNixosSystem { inherit (value) hostName; })
        hosts;

      # ========================================================================
      # OUTPUT 2: colmena (raw hive configuration)
      # ========================================================================
      colmena = import ./colmena.nix {
        inherit inputs self;
        inherit hosts;
      };

      # ========================================================================
      # OUTPUT 3: colmenaHive (for multi-host deployment)
      # Wraps the raw hive configuration with makeHive for proper schema
      # ========================================================================
      colmenaHive = colmena.lib.makeHive self.outputs.colmena;

      # ========================================================================
      # EXISTING OUTPUTS (maintain compatibility)
      # ========================================================================
      packages.x86_64-linux.claude = claude-native.packages.x86_64-linux.claude;

      overlays.default = import ./overlay.nix;

      apps.x86_64-linux.colmena = {
        type = "app";
        program = "${colmena.packages.x86_64-linux.colmena}/bin/colmena";
      };
    };
}
