{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-xr.url = "github:nix-community/nixpkgs-xr";
    nixpkgs-xr.inputs.nixpkgs.follows = "nixpkgs";

    # CachyOS Kernel - x86_64-v3/v2 variants (actively maintained)
    # Use release branch for binary cache availability
    cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Zen Browser Flake
    zen-browser.url = "github:0xc000022070/zen-browser-flake/231ae41b0cd867046ff0bc3c1a7707e244fe8127";
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
    aagl.inputs.nixpkgs.follows = "nixpkgs"; # CRITICAL: Must follow for mkRenamedOptionModule to work

    # ScopeBuddy - Gamescope wrapper for Wayland desktop gaming
    scopebuddy.url = "github:OpenGamingCollective/ScopeBuddy";
    scopebuddy.inputs.nixpkgs.follows = "nixpkgs";

    # Claude Code Native Binary
    claude-native.url = "github:ryoppippi/claude-code-overlay";
    claude-native.inputs.nixpkgs.follows = "nixpkgs";

    # Agenix - Age-encrypted secrets for NixOS
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    # Determinate Nix module
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    # OpenCode AI Agent
    opencode.url = "github:anomalyco/opencode/dev";

    # Nix Flatpak - Declarative Flatpak management
    nix-flatpak.url = "github:gmodena/nix-flatpak";

    # Stylix - Declarative theming for NixOS
    stylix.url = "github:danth/stylix/master";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    # base16.nix - Base16/Base24 theming library (used by Stylix, exposed for direct access)
    base16.url = "github:SenchoPens/base16.nix";

    # tinted-schemes - Base16 and Base24 color schemes from tinted-theming
    tinted-schemes = {
      url = "github:tinted-theming/schemes";
      flake = false;
    };

    # HyperWhisper - Real-time speech-to-text desktop app
    hyperwhisper.url = "path:/etc/nixos/external/hyperwhisper";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }: let
    # Common modules shared across all hosts, inlined here for clarity
    commonModules = [
      # Stylix MUST be first - it initializes the stylix option namespace
      # that other modules depend on
      inputs.stylix.nixosModules.stylix

      # Enable Stylix system-wide with Tokyo City Dark theme
      ({pkgs, ...}: {
        stylix = {
          enable = true;
          base16Scheme = "${pkgs.base16-schemes}/share/themes/tokyo-city-terminal-dark.yaml";

          # Disable Stylix Qt theming - it sets QT_STYLE_OVERRIDE=kvantum which breaks Plasma 6
          # with "module 'kvantum' is not installed" errors in QML
          targets.qt.enable = false;

          # Beautiful font stack: Inter (UI) + JetBrains Mono (terminal)
          fonts = {
            serif = {
              name = "DejaVu Serif";
              package = pkgs.dejavu_fonts;
            };
            sansSerif = {
              name = "Inter";
              package = pkgs.inter;
            };
            monospace = {
              name = "JetBrains Mono NF";
              package = pkgs.nerd-fonts.jetbrains-mono;
            };
            emoji = {
              name = "Noto Color Emoji";
              package = pkgs.noto-fonts-color-emoji;
            };
          };
        };
      })

      # External Modules (must come before common-base.nix)
      inputs.aagl.nixosModules.default
      inputs.determinate.nixosModules.default
      inputs.nix-gaming.nixosModules.pipewireLowLatency
      inputs.nix-gaming.nixosModules.platformOptimizations
      inputs.agenix.nixosModules.default
      inputs.nix-flatpak.nixosModules.nix-flatpak

      # Base Configuration (after external modules)
      ./common-base.nix

      # Local Modules
      # garnix.nix moved to host-specific imports to avoid nix.settings conflicts

      # Home Manager
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.j_kro = {...}: {
          imports = [
            ./home.nix
            # NOTE: stylix.homeModules.stylix is auto-imported by NixOS module
            # via stylix.homeManagerIntegration.autoImport (default = true)
          ];
        };
        home-manager.backupFileExtension = "hm-backup";
        home-manager.extraSpecialArgs = {inherit inputs;};
      }

      # Common Overlays & Config
      {
        nixpkgs.overlays = [
          self.overlays.default
          inputs.cachyos-kernel.overlays.pinned
        ];
        nixpkgs.config.allowUnfree = true;
        nixpkgs.config.permittedInsecurePackages = [
          "electron-25.9.0"
        ];

        # ezKEa aagl-gtk-on-nix Cachix + CachyOS binary cache
        nix.settings = {
          substituters = [
            "https://attic.xuyh0120.win/lantian"
            "https://cache.garnix.io"
          ];
          trusted-public-keys = [
            "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
            "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
          ];
        };
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
    overlays.default = import ./modules/mining/mining-overlay.nix;

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

    # Colmena app for deployment
    # Use colmena from flake input to match hive schema version
    apps.x86_64-linux.colmena = {
      type = "app";
      program = "${inputs.colmena.packages.x86_64-linux.colmena}/bin/colmena";
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
