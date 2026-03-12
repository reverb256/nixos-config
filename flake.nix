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

      # Overlays configuration - applies overlays.default to all hosts
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
        specialArgs = {inherit inputs;};
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
      builtins.mapAttrs
      (_name: value: mkNixosSystem {inherit (value) hostName;})
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

      config = {
        Entrypoint = ["/bin/lolminer"];
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
