{inputs}: {
  imports = [
    ./hosts/zephyr/configuration.nix
    ./hosts/nexus/configuration.nix
    ./hosts/forge/configuration.nix
    ./hosts/sentry/configuration.nix
  ];

  nixosConfigurations = {
    zephyr = {
      modules = [
        {
          networking.hostName = "zephyr";
        }
        inputs.ezkea.nixosModules.default
        inputs.agenix.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        ./secrets/age-secrets.nix
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.j_kro = {
            imports = [./home.nix];
          };
        }
      ];
    };

    nexus = {
      modules = [
        {
          networking.hostName = "nexus";
        }
        inputs.ezkea.nixosModules.default
        inputs.agenix.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        ./secrets/age-secrets.nix
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.j_kro = {
            imports = [./home.nix];
          };
        }
      ];
    };

    forge = {
      modules = [
        ./configuration.nix
        ./hosts/forge/hardware-configuration.nix
        {
          networking.hostName = "forge";
        }
        inputs.ezkea.nixosModules.default
        inputs.agenix.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        ./secrets/age-secrets.nix
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.j_kro = {
            imports = [./home.nix];
          };
        }
      ];
    };

    sentry = {
      modules = [
        {
          networking.hostName = "sentry";
        }
        inputs.ezkea.nixosModules.default
        inputs.agenix.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        ./secrets/age-secrets.nix
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.j_kro = {
            imports = [./home.nix];
          };
        }
      ];
    };
  };

  overlays = [
    inputs.self.overlays.mining-overlay
    (inputs.claude-native.overlay or (_: _: {}))
    (final: _prev: {
      # Enhanced Claude Code with MCP support
      inherit (final) claude;
    })
  ];

  config = {
    # Common Nix configuration for all hosts
    # Note: max-jobs and cores are configured in modules/nix-config.nix per-host
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://ezkea.cachix.org"
        "https://nixpkgs-wayland.cachix.org"
        "https://nix-gaming.cachix.org"
        "https://cuda-maintainers.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
        "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
        "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      ];
    };
  };
}
