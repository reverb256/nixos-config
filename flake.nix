{
  description = "NixOS configuration with Garage and Syncthing storage";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
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
    # nixpkgs-xr - Disabled due to deprecated options in systems module
    # Only used for proton-ge-rtsp-bin and oscavmgr (VR packages)
    # Re-enable when nixpkgs-xr updates their systems dependency
    # nixpkgs-xr = {
    #   url = "github:nix-community/nixpkgs-xr";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    scopebuddy = {
      url = "github:OpenGamingCollective/ScopeBuddy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcord = {
      url = "github:FlameFlag/nixcord";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # spicetify-nix - Disabled due to deprecated options in systems dependency
    # Not currently used in configuration
    # spicetify-nix = {
    #   url = "github:Gerg-L/spicetify-nix";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    agenix = {
      url = "github:ryantm/agenix/0.15.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Colmena - Multi-host deployment
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-stable,
    home-manager,
    aagl,
    nur,
    claude-native,
    agenix,
    colmena,
    ...
  }: let
    # System configuration
    system = "x86_64-linux";

    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    # ========================================================================
    # x86-64-v3 MICROARCHITECTURE NOTES
    # ========================================================================
    # All cluster CPUs support AVX2 and v3 requirements:
    # - Zephyr: Ryzen 9 5950X (Zen 3)
    # - Nexus: Ryzen 9 3900X (Zen 2)
    # - Forge: i5-9500 (Coffee Lake)
    # - Sentry: Ryzen 7 1700 (Zen 1, has AVX2)
    #
    # Benefits: 10-30% SIMD performance uplift for AI, mining, crypto
    # Cost: No binary cache compatibility (must build from source)
    #
    # Implementation: v3 is set via nixpkgs.hostPlatform.gcc.arch at module
    # level in mkNixosSystemV3 below (NOT via localSystem in flake imports).

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

      # ========================================================================
      # OVERLAYS CONFIGURATION
      # ========================================================================
      # Custom package overlays applied to ALL hosts
      #
      # Scope: System + Home Manager (due to useGlobalPkgs = true)
      # Location: ./overlay.nix defines custom packages (lolminer, xmrig, etc.)
      #
      # Why here? Single definition point prevents duplication and ensures
      # all hosts have access to custom packages. When useGlobalPkgs=true,
      # Home Manager uses the same pkgs instance as the system, so this
      # overlay affects both system packages and user packages.
      #
      # See: modules/system/home-manager.nix for useGlobalPkgs setting
      # ========================================================================
      {nixpkgs.overlays = [self.overlays.default];}
    ];

    # ========================================================================
    # HELPER FUNCTION - Create NixOS system (eliminates duplication)
    # ========================================================================
    mkNixosSystem = {
      hostName,
      extraModules ? [],
    }:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
          # Import stable nixpkgs for packages with known issues in unstable
          pkgs-stable = import nixpkgs-stable {
            inherit system;
            config.allowUnfree = true;
          };
        };
        modules =
          commonModules
          ++ [
            ./hosts/${hostName}/configuration.nix

            # Allow unsupported packages (CUDA 12 for LM Studio)
            {nixpkgs.config.allowUnsupportedSystem = true;}
          ]
          ++ extraModules;
      };

    # ========================================================================
    # x86-64-v3 MICROARCHITECTURE NOTES
    # ========================================================================
    # All cluster CPUs support AVX2 and v3 requirements:
    # - Zephyr: Ryzen 9 5950X (Zen 3)
    # - Nexus: Ryzen 9 3900X (Zen 2)
    # - Forge: i5-9500 (Coffee Lake)
    # - Sentry: Ryzen 7 1700 (Zen 1, has AVX2)
    #
    # Benefits: 10-30% SIMD performance uplift for AI, mining, crypto
    # Cost: No binary cache compatibility (must build from source)
    #
    # Implementation: Module-level nixpkgs.hostPlatform.gcc.arch (NOT localSystem)
    # The system-features = ["gccarch-x86-64-v3"] is declared in
    # modules/common-host-defaults.nix to enable sandbox access.
    # ========================================================================

    # Helper to build v3 NixOS system
    # Uses module-level nixpkgs.hostPlatform.gcc.arch for microarch tuning
    mkNixosSystemV3 = {
      hostName,
      extraModules ? [],
    }:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
          # Import stable nixpkgs for packages with known issues in unstable
          pkgs-stable = import nixpkgs-stable {
            inherit system;
            config.allowUnfree = true;
          };
        };
        modules =
          commonModules
          ++ [
            ./hosts/${hostName}/configuration.nix
            {
              # Set v3 microarchitecture at module level
              # This configures stdenv to use -march=x86-64-v3
              # Full hostPlatform config is required (system + gcc.arch)
              nixpkgs.hostPlatform = {
                system = "x86_64-linux";
                gcc.arch = "x86-64-v3";
              };

              # Set system-features ONLY for v3 configurations
              # This allows building v3-optimized packages when explicitly requested
              # CRITICAL: Do NOT set this globally or binary caches won't work!
              nix.settings.system-features = ["gccarch-x86-64-v3"];
            }
          ]
          ++ extraModules;
      };

    # ========================================================================
    # HOST DEFINITIONS - Single source of truth
    # ========================================================================
    hosts = {
      zephyr = {hostName = "zephyr";};
      nexus = {hostName = "nexus";};
      forge = {hostName = "forge";};
      sentry = {hostName = "sentry";};
    };
  in {
    # ========================================================================
    # OUTPUT 1: nixosConfigurations (for local nixos-rebuild)
    # ========================================================================
    nixosConfigurations =
      # Baseline configurations (no microarchitecture tuning)
      builtins.mapAttrs
      (_name: value: mkNixosSystem {inherit (value) hostName;})
      hosts
      // {
        # x86-64-v3 configurations (suffix: -v3)
        # Use: sudo nixos-rebuild switch --flake .#nexus-v3
        nexus-v3 = mkNixosSystemV3 {hostName = "nexus";};
        zephyr-v3 = mkNixosSystemV3 {hostName = "zephyr";};
        forge-v3 = mkNixosSystemV3 {hostName = "forge";};
        sentry-v3 = mkNixosSystemV3 {hostName = "sentry";};
      };

    # ========================================================================
    # OUTPUT 1.5: nixosConfigurationsV3 (x86-64-v3 microarchitecture)
    # ========================================================================
    # Kept for Colmena and programmatic access
    nixosConfigurationsV3 =
      builtins.mapAttrs
      (_name: value: mkNixosSystemV3 {inherit (value) hostName;})
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

    # ========================================================================
    # CONTAINER IMAGES (for Kubernetes deployment)
    # ========================================================================
    packages.x86_64-linux.xmrig-proxy-image = pkgs.dockerTools.buildImage {
      name = "xmrig-proxy";
      tag = "nixos-6.24.0";

      copyToRoot = pkgs.buildEnv {
        name = "xmrig-proxy-root";
        paths = [
          pkgs.xmrig-proxy
          pkgs.bash
          pkgs.coreutils
          pkgs.cacert
        ];
        pathsToLink = ["/bin" "/etc" "/lib"];
      };

      config = {
        Entrypoint = ["/bin/xmrig-proxy"];
        Cmd = ["--config=/etc/xmrig-proxy/config.json" "--no-color"];

        ExposedPorts = {
          "3333/tcp" = {}; # Stratum port
          "8081/tcp" = {}; # API port
        };

        Env = [
          "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
          "PATH=/bin"
        ];
      };
    };

    # TODO: lolminer package not available - commented out to unblock deployments
    # Re-enable after verifying lolminer overlay is properly applied
    # packages.x86_64-linux.lolminer-image = pkgs.dockerTools.buildImage {
    #   name = "lolminer";
    #   tag = "1.98a-nixos";
    #
    #   copyToRoot = pkgs.buildEnv {
    #     name = "lolminer-root";
    #     paths = [
    #       pkgs.lolminer
    #       pkgs.bash
    #       pkgs.coreutils
    #       pkgs.cacert
    #     ];
    #     pathsToLink = ["/bin" "/etc" "/lib"];
    #   };
    #
    #   config = {
    #     Entrypoint = ["/bin/lolMiner"];
    #     Cmd = [];
    #
    #     ExposedPorts = {
    #       "4068/tcp" = {}; # API port
    #     };
    #
    #     Env = [
    #       "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    #       "PATH=/bin"
    #       "GPU_MAX_HEAP_SIZE=100"
    #       "GPU_MAX_ALLOC_PERCENT=100"
    #     ];
    #   };
    # };

    overlays.default = import ./overlay.nix;

    apps.x86_64-linux.colmena = {
      type = "app";
      program = "${colmena.packages.x86_64-linux.colmena}/bin/colmena";
    };
  };
}
