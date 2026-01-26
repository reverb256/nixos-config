{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-xr.url = "github:nix-community/nixpkgs-xr";
    nixpkgs-xr.inputs.nixpkgs.follows = "nixpkgs";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Zen Browser Flake
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
    zen-browser.inputs.home-manager.follows = "home-manager";

    # Anime Games Launcher (ezKEa)
    ezkea.url = "github:ezKEa/aagl-gtk-on-nix";

    # Nixcord - Declarative Discord/Vesktop configuration
    nixcord.url = "github:FlameFlag/nixcord";

    # Enhanced Gaming Packages (Proton-GE, GameMode, etc.)
    nix-gaming.url = "github:fufexan/nix-gaming";

    # Claude Code Native Binary
    claude-native.url = "github:ryoppippi/claude-code-overlay";
    claude-native.inputs.nixpkgs.follows = "nixpkgs";

    # Agenix - Age-encrypted secrets for NixOS
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    nix-gaming.inputs.nixpkgs.follows = "nixpkgs";

    # Determinate Nix module
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    # OpenCode AI Agent
    opencode.url = "github:anomalyco/opencode/dev";

    # Colmena - Multi-host deployment
    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }: let
    # Common modules shared across all hosts, inlined here for clarity
    commonModules = [
      # Base Configuration
      ./configuration.nix

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
        home-manager.users.j_kro = import ./home.nix; # Assuming home.nix is in root
        home-manager.extraSpecialArgs = {inherit inputs;};
      }

      # Common Overlays & Config
      {
        nixpkgs.overlays = [self.overlays.default];
        nixpkgs.config.allowUnfree = true;
        nixpkgs.config.permittedInsecurePackages = [
          "electron-25.9.0"
        ];
      }
    ];

    # Function to create a Colmena node definition
    mkColmenaNode = {
      name,
      targetHost,
      modules ? [],
    }: {
      imports = commonModules ++ modules;
      deployment = {
        targetHost = targetHost;
        targetUser = "j_kro";
        buildOnReplacement = true;
        ssh.keys = ["~/.ssh/id_ed25519"];
        tags = ["default"]; # Default tag for colmena apply
      };
    };

    # Function to create a NixOS system definition
    mkNixosSystem = {modules ? []}:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        # Pass all inputs to specialArgs for modules to use
        specialArgs = {inherit inputs;};
        modules = commonModules ++ modules; # Common modules are now inlined
      };

    # Host definitions for Colmena
    colmenaNodes = {
      zephyr = mkColmenaNode {
        name = "zephyr";
        targetHost = "10.1.1.110";
      };
      nexus = mkColmenaNode {
        name = "nexus";
        targetHost = "10.1.1.120";
      };
      forge = mkColmenaNode {
        name = "forge";
        targetHost = "10.1.1.130";
      };
      sentry = mkColmenaNode {
        name = "sentry";
        targetHost = "10.1.1.140";
      };
    };

    # NixOS system definitions
    nixosSystems = {
      zephyr = mkNixosSystem {
        modules = [./hosts/zephyr/configuration.nix];
      };
      nexus = mkNixosSystem {
        modules = [./hosts/nexus/configuration.nix];
      };
      forge = mkNixosSystem {
        modules = [./hosts/forge/configuration.nix];
      };
      sentry = mkNixosSystem {
        modules = [./hosts/sentry/configuration.nix];
      };
    };
  in {
    # Shared overlays
    overlays.default = import ./modules/mining-overlay.nix;

    # Colmena output
    # Colmena output
    colmena = {
      meta = {
        nixpkgs = import inputs.nixpkgs {
          system = "x86_64-linux";
          overlays = [self.overlays.default];
          config.allowUnfree = true;
        };
        specialArgs = {inherit inputs;};
      };

      # Define Colmena nodes directly in the colmena output
      zephyr = {
        imports = commonModules ++ [./hosts/zephyr/configuration.nix];
        deployment = {
          targetHost = "10.1.1.110";
          targetUser = "j_kro";
          buildOnReplacement = true;
          ssh.keys = ["~/.ssh/id_ed25519"];
          tags = ["default"];
        };
      };

      nexus = {
        imports = commonModules ++ [./hosts/nexus/configuration.nix];
        deployment = {
          targetHost = "10.1.1.120";
          targetUser = "j_kro";
          buildOnReplacement = true;
          ssh.keys = ["~/.ssh/id_ed25519"];
          tags = ["default"];
        };
      };

      forge = {
        imports = commonModules ++ [./hosts/forge/configuration.nix];
        deployment = {
          targetHost = "10.1.1.130";
          targetUser = "j_kro";
          buildOnReplacement = true;
          ssh.keys = ["~/.ssh/id_ed25519"];
          tags = ["default"];
        };
      };

      sentry = {
        imports = commonModules ++ [./hosts/sentry/configuration.nix];
        deployment = {
          targetHost = "10.1.1.140";
          targetUser = "j_kro";
          buildOnReplacement = true;
          ssh.keys = ["~/.ssh/id_ed25519"];
          tags = ["default"];
        };
      };
    };

    # NixOS configurations (for direct use with nixos-rebuild)
    nixosConfigurations = nixosSystems;

    packages.x86_64-linux.claude = inputs.claude-native.packages.x86_64-linux.default;
  };
}
