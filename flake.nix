{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-xr.url = "github:nix-community/nixpkgs-xr";
    nixpkgs-xr.inputs.nixpkgs.follows = "nixpkgs";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Zen Browser Flake - PINNED to current version
    # Last updated: 2026-01-29
    # To update: Remove the rev parameter and run: nix flake update zen-browser
    zen-browser.url = "github:0xc000022070/zen-browser-flake/e97c8e719c7e2567ccf86d279f73ade1dbf72373";
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

    # Kimi Code CLI - AI coding agent
    kimi-cli.url = "github:MoonshotAI/kimi-cli";
    kimi-cli.inputs.nixpkgs.follows = "nixpkgs";

    # OpenClaw - Personal AI assistant
    nix-openclaw.url = "github:openclaw/nix-openclaw";
    nix-openclaw.inputs.nixpkgs.follows = "nixpkgs";
    nix-openclaw.inputs.home-manager.follows = "home-manager";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    kimi-cli,
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
        buildOnTarget = true;
        keys = ["~/.ssh/id_ed25519"];
        tags = ["default"]; # Default tag for colmena apply
      };
    };

    # Common modules WITHOUT home-manager (for fast builds)
    commonModulesFast = [
      # Base Configuration
      ./configuration.nix

      # External Modules (without home-manager)
      inputs.ezkea.nixosModules.default
      inputs.determinate.nixosModules.default
      inputs.nix-gaming.nixosModules.pipewireLowLatency
      inputs.nix-gaming.nixosModules.platformOptimizations
      inputs.agenix.nixosModules.default

      # Common Overlays & Config
      {
        nixpkgs.overlays = [self.overlays.default];
        nixpkgs.config.allowUnfree = true;
        nixpkgs.config.permittedInsecurePackages = [
          "electron-25.9.0"
        ];
      }
    ];

    # Function to create a NixOS system definition
    mkNixosSystem = {
      modules ? [],
      fast ? false,
    }:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        # Pass all inputs to specialArgs for modules to use
        specialArgs = {inherit inputs;};
        modules =
          (
            if fast
            then commonModulesFast
            else commonModules
          )
          ++ modules;
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
      # Fast variant without home-manager for quick system updates
      zephyr-fast = mkNixosSystem {
        modules = [./hosts/zephyr/configuration.nix];
        fast = true;
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

    # NixOS configurations (for direct use with nixos-rebuild)
    nixosConfigurations = nixosSystems;

    # Formatter for nix fmt
    formatter.x86_64-linux = inputs.nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;

    packages.x86_64-linux = {
      claude = inputs.claude-native.packages.x86_64-linux.default;
      kimi = inputs.kimi-cli.packages.x86_64-linux.default;
    };
  };
}
