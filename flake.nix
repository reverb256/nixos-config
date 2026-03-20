{
  description = "NixOS configuration with Garage and Syncthing storage";

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

    # Hermes Agent - Multi-node deployment agent
    hermes-agent = {
      url = "github:NousResearch/hermes-agent/main";
      flake = false;
      # Fetch submodules for minisweagent, tinker-atropos, etc.
      # Using git input type to enable submodules
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
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
      config.cudaSupport = true; # Enable CUDA in source packages (PyTorch, TensorFlow, etc.)
    };

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

      # ========================================================================
      # AGENIX IDENTITY PATHS - Cluster-wide secret decryption
      # ========================================================================
      # Priority: Syncthing-synced > System > Home directory
      #
      # /etc/nixos/.age/key.txt - Synced via Syncthing across all hosts
      # /etc/age/key.txt - System location (fallback, populated by activation script)
      # /home/j_kro/.age/key.txt - Original location (Zephyr only)
      # ========================================================================
      {
        age.identityPaths = [
          "/etc/nixos/.age/key.txt"
          "/etc/age/key.txt"
          "/home/j_kro/.age/key.txt"
        ];
      }
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
          inherit (inputs) hermes-agent;
        };
        modules =
          commonModules
          ++ [
            ./hosts/${hostName}/configuration.nix
          ]
          ++ extraModules;
      };

    # ========================================================================
    # HOST DEFINITIONS - Single source of truth
    # ========================================================================
    hosts = {
      zephyr = {
        hostName = "zephyr";
      };
      nexus = {
        hostName = "nexus";
      };
      forge = {
        hostName = "forge";
      };
      sentry = {
        hostName = "sentry";
      };
    };
  in {
    # ========================================================================
    # OUTPUT 1: nixosConfigurations (for local nixos-rebuild)
    # ========================================================================
    nixosConfigurations =
      builtins.mapAttrs (
        _name: value: mkNixosSystem {inherit (value) hostName;}
      )
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
    packages.x86_64-linux.llama-cpp = pkgs.llama-cpp;

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
        pathsToLink = [
          "/bin"
          "/etc"
          "/lib"
        ];
      };

      config = {
        Entrypoint = ["/bin/xmrig-proxy"];
        Cmd = [
          "--config=/etc/xmrig-proxy/config.json"
          "--no-color"
        ];

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

    packages.x86_64-linux.lolminer-image = pkgs.dockerTools.buildImage {
      name = "lolminer";
      tag = "1.98a-nixos";

      copyToRoot = pkgs.buildEnv {
        name = "lolminer-root";
        paths = [
          pkgs.lolminer
          pkgs.bash
          pkgs.coreutils
          pkgs.cacert
        ];
        pathsToLink = ["/bin" "/etc" "/lib"];
      };

      config = {
        Entrypoint = ["/bin/lolMiner"];
        Cmd = [];

        ExposedPorts = {
          "4068/tcp" = {}; # API port
        };

        Env = [
          "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
          "PATH=/bin"
          "GPU_MAX_HEAP_SIZE=100"
          "GPU_MAX_ALLOC_PERCENT=100"
        ];
      };
    };

    overlays.default = import ./overlay.nix;

    apps.x86_64-linux.colmena = {
      type = "app";
      program = "${colmena.packages.x86_64-linux.colmena}/bin/colmena";
    };
  };
}
