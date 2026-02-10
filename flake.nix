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

    # Nixcord - Declarative Discord/Vesktop configuration
    nixcord.url = "github:FlameFlag/nixcord";
 
    # Colmena - Multi-host deployment (v0.5+ requires colmenaHive output)
    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";
 
    # Enhanced Gaming Packages (Proton-GE, GameMode, etc.)
    nix-gaming.url = "github:fufexan/nix-gaming";

    # Anime Game Launchers (ezKEa/aagl-gtk-on-nix)
    aagl.url = "github:ezKEa/aagl-gtk-on-nix";

    # ScopeBuddy - Gamescope wrapper for Wayland desktop gaming
    scopebuddy.url = "github:OpenGamingCollective/ScopeBuddy";
    scopebuddy.inputs.nixpkgs.follows = "nixpkgs";

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
 
    # Nix Flatpak - Declarative Flatpak management
    nix-flatpak.url = "github:gmodena/nix-flatpak";

    # CachyOS Kernel - BORE scheduler for gaming
    nix-cachyos-kernel.url = "github:drakon64/nixos-cachyos-kernel";
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
      inputs.aagl.nixosModules.default
      inputs.determinate.nixosModules.default
      inputs.nix-gaming.nixosModules.pipewireLowLatency
      inputs.nix-gaming.nixosModules.platformOptimizations
      inputs.agenix.nixosModules.default
      inputs.nix-flatpak.nixosModules.nix-flatpak

      # Local Modules
      ./modules/garnix.nix

      # Home Manager
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.j_kro = import ./home.nix; # Assuming home.nix is in root
        home-manager.backupFileExtension = "bak";
        home-manager.extraSpecialArgs = {inherit inputs;};
      }

      # Common Overlays & Config
      {
        nixpkgs.overlays = [
          self.overlays.default
        ];
        nixpkgs.config.allowUnfree = true;
        nixpkgs.config.permittedInsecurePackages = [
          "electron-25.9.0"
        ];

        # ezKEa aagl-gtk-on-nix Cachix
        nix.settings = inputs.aagl.nixConfig;
      }
    ];

    # Function to create a NixOS system definition
    mkNixosSystem = {modules ? []}:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        # Pass all inputs to specialArgs for modules to use
        specialArgs = {inherit inputs;};
        modules = commonModules ++ modules;
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

    # Add nixpkgs-xr overlay for VR/gaming packages
    overlays.nixpkgs-xr = inputs.nixpkgs-xr.overlays.default;

    # NixOS configurations (for direct use with nixos-rebuild)
    nixosConfigurations = nixosSystems;

    # Colmena v0.5+ configuration
    colmena = import ./colmena.nix {
      inherit inputs self;
    };

    # Colmena v0.5+ requires colmenaHive output
    colmenaHive = inputs.colmena.lib.makeHive self.outputs.colmena;

    # Formatter for nix fmt
    formatter.x86_64-linux = inputs.nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;

    packages.x86_64-linux = {
      claude = inputs.claude-native.packages.x86_64-linux.default;
    };

    # Development shell with all NixOS tools
    devShells.x86_64-linux.default = inputs.nixpkgs.legacyPackages.x86_64-linux.mkShell {
      name = "nixos-config";

      packages = with inputs.nixpkgs.legacyPackages.x86_64-linux; [
        # Nix tools
        nixfmt-tree
        alejandra
        deadnix
        statix
        nixd

        # Git tools
        git
        gh

        # Build tools
        just
        colmena

        # Secrets management
        age
        ssh-to-age
        sops

        # Cloud/Cache tools
        minio-client
        rclone

        # System tools
        jq
        yq
        curl
        wget

        # Script quality
        shellcheck

        # Documentation
        mdsh
      ];

      shellHook = ''
        echo "🚀 NixOS Config Development Environment"
        echo ""
        echo "Available commands:"
        echo "  just              - Run just recipes"
        echo "  colmena           - Deploy to cluster"
        echo "  deadnix .         - Find dead Nix code"
        echo "  statix check .    - Lint Nix files"
        echo "  alejandra .       - Format Nix files"
        echo "  shellcheck .      - Check shell scripts"
        echo "  mc                - MinIO client"
        echo ""
        echo "Hosts: zephyr, nexus, forge, sentry"
        echo "Cache: http://10.1.1.120:9000 (nexus AIStor)"
      '';
    };
  };
}
