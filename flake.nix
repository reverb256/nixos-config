{
  description = "NixOS configuration with Garage and Syncthing storage";
  inputs = {
    nixpkgs.url = "tarball+https://codeload.github.com/NixOS/nixpkgs/tar.gz/9ae611a455b90cf061d8f332b977e387bda8e1ca"; # pinned: predates nixos-unstable pkgs-fixedPoint recursion regression
    home-manager = {
      url = "git+https://github.com/nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "git+https://github.com/0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aagl = {
      url = "git+https://github.com/ezKEa/aagl-gtk-on-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "git+https://github.com/nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    claude-native = {
      url = "git+https://github.com/ryoppippi/claude-code-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixpkgs-xr - Bleeding-edge XR/VR packages (WiVRn, Monado, libsurvive, xrizer, etc.)
    # Provides binary cache at nix-community.cachix.org
    nixpkgs-xr = {
      url = "git+https://github.com/nix-community/nixpkgs-xr";
    };
    scopebuddy = {
      url = "git+https://github.com/OpenGamingCollective/ScopeBuddy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcord = {
      url = "git+https://github.com/FlameFlag/nixcord";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # spicetify-nix - Disabled due to deprecated options in systems dependency
    # Not currently used in configuration
    # spicetify-nix = {
    #   url = "git+https://github.com/Gerg-L/spicetify-nix";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    agenix = {
      url = "git+https://github.com/ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    sops-nix = {
      url = "git+https://github.com/Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Use git+https:// for github inputs to avoid GitHub API 401 errors (prevalent in Lix 2.95)
    systems = {
      url = "git+https://github.com/nix-systems/default";
      flake = false;
    };
    # Colmena - Multi-host deployment
    colmena = {
      url = "git+https://github.com/zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Niri - Scrollable-tiling Wayland compositor
    # Provides: programs.niri NixOS module, niri-unstable overlay, home-manager module
    niri = {
      url = "git+https://github.com/sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # llm-agents.nix - Nix packages for AI coding agents (Droid, etc.)
    llm-agents = {
      url = "git+https://github.com/numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    # CachyOS kernel - Performance-optimized kernel for gaming/desktop (Zephyr only)
    # Provides: linux-cachyos-latest-x86_64-v3, sched_ext support, BORE scheduler
    # Binary cache: attic.xuyh0120.win/lantian (no local compilation needed)
    nix-cachyos-kernel.url = "git+https://github.com/xddxdd/nix-cachyos-kernel";
    nix-cachyos-kernel.inputs.flake-parts.follows = "flake-parts";
    # linux-cachyos override — may not exist in all kernel flake versions, non-fatal if ignored
    # ── Inputs required by common-modules-list.nix (re-added after a drift where
    #    they were dropped from flake.nix but still referenced in the module list) ──
    # hermes-agent - Hermes Agent NixOS module + packages
    hermes-agent = {
      url = "git+https://github.com/NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    # mcp-registry - MCP server registry module (local tarball: nix HTTPS fetcher stalls)
    mcp-registry = {
      url = "tarball+file:///tmp/mcp-registry.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # caddy-ingress - Caddy ingress module + caddy-with-modules package (local tarball)
    caddy-ingress = {
      url = "tarball+file:///tmp/caddy-ingress.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # ai-gateway - AI inference gateway package (local tarball)
    ai-gateway = {
      url = "tarball+file:///tmp/ai-gateway.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # gpu-proxy - GPU proxy module (local tarball)
    gpu-proxy = {
      url = "tarball+file:///tmp/gpu-proxy.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # flake-parts — transitive dep for 6 inputs, use git+https to bypass GitHub API 401
    flake-parts = {
      url = "git+https://github.com/hercules-ci/flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # noctalia - brightness daemon for NixOS
    noctalia = {
      url = "git+https://github.com/noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # stylix - theming module (local tarball)
    stylix = {
      url = "tarball+file:///tmp/stylix.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      aagl,
      nur,
      claude-native,
      agenix,
      colmena,
      nixpkgs-xr,
      ...
    }:
    let
      # System configuration
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      # pkgsWithOverlay: nixpkgs with custom overlay applied
      pkgsWithOverlay = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ (import ./overlay.nix { inherit inputs; }) ];
      };

      # COMMON MODULES - Shared across all hosts (single source of truth)

      # Import from shared file to ensure flake.nix and colmena.nix stay in sync
      commonModules = import ./common-modules-list.nix {
        inherit inputs self;
      };

      # HELPER FUNCTION - Create NixOS system (eliminates duplication)

      mkNixosSystem =
        {
          hostName,
          extraModules ? [ ],
        }:
        nixpkgs.lib.nixosSystem {
          # system is auto-detected from stdenv.hostPlatform
          specialArgs = {
            inherit inputs;
          };
          modules =
            commonModules
            ++ [
              ./hosts/${hostName}/configuration.nix
            ]
            ++ extraModules;
        };

      # HOST DEFINITIONS - Single source of truth

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
    in
    {

      # OUTPUT 1: nixosConfigurations (for local nixos-rebuild)

      nixosConfigurations = builtins.mapAttrs (
        _name: value: mkNixosSystem { inherit (value) hostName; }
      ) hosts;

      # OUTPUT 2: colmena (raw hive configuration)

      colmena = import ./colmena.nix {
        inherit inputs self;
        inherit hosts;
      };

      # OUTPUT 3: colmenaHive (for multi-host deployment)
      # Wraps the raw hive configuration with makeHive for proper schema

      colmenaHive = colmena.lib.makeHive self.outputs.colmena;

      # EXISTING OUTPUTS (maintain compatibility)

      packages.x86_64-linux.claude = claude-native.packages.x86_64-linux.claude;
      packages.x86_64-linux.llama-cpp = pkgs.llama-cpp;
      # CONTAINER IMAGES (for Kubernetes deployment)

      # Claude Code container image for Kubernetes deployment
      packages.x86_64-linux.claude-code-image = pkgs.dockerTools.buildImage {
        name = "claude-code";
        tag = "nixos";
        copyToRoot = pkgs.buildEnv {
          name = "claude-code-root";
          paths = [
            pkgs.claude-code
            pkgs.bash
            pkgs.coreutils
            pkgs.fish
            pkgs.git
            pkgs.gnugrep
            pkgs.gnused
          ];
          pathsToLink = [
            "/bin"
            "/etc"
            "/lib"
          ];
        };
        config = {
          Cmd = [
            "${pkgs.bash}/bin/bash"
            "-c"
            "mkdir -p /home/j_kro/.claude && tail -f /dev/null"
          ];
          WorkingDir = "/home/j_kro";
          Env = [
            "HOME=/home/j_kro"
            "USER=j_kro"
            "PATH=/bin"
            "CLAUDE_CONFIG_DIR=/home/j_kro/.claude"
            "SHELL=/bin/fish"
          ];
          ExposedPorts = {
            "8080/tcp" = { };
          };
          Labels = {
            "org.opencontainers.image.title" = "Claude Code";
            "org.opencontainers.image.description" = "Claude Code AI coding assistant";
          };
        };
      };
      packages.x86_64-linux.ai-inference-gateway-image =
        pkgs.callPackage ./pkgs/ai-inference-gateway-image
          { };
      # Requires impure paths - build manually: nix build .#kb-mcp-image --impure
      # packages.x86_64-linux.kb-mcp-image = pkgs.callPackage ./pkgs/kb-mcp-image { };
      packages.x86_64-linux.opencode-image = pkgs.dockerTools.buildImage {
        name = "opencode";
        tag = "nixos";
        copyToRoot = pkgs.buildEnv {
          name = "opencode-root";
          paths = [
            pkgs.opencode
            pkgs.bash
            pkgs.coreutils
            pkgs.fish
            pkgs.git
          ];
          pathsToLink = [
            "/bin"
            "/etc"
            "/lib"
            "/home/j_kro/.nix-profile"
          ];
        };
        config = {
          Cmd = [
            "${pkgs.bash}/bin/bash"
            "-c"
            "mkdir -p /home/j_kro/.opencode && tail -f /dev/null"
          ];
          WorkingDir = "/home/j_kro";
          Env = [
            "HOME=/home/j_kro"
            "USER=j_kro"
            "PATH=/home/j_kro/.nix-profile/bin:/bin"
            "OPENCODE_CONFIG_DIR=/home/j_kro/.opencode"
            "SHELL=/bin/fish"
          ];
          Labels = {
            "org.opencontainers.image.title" = "OpenCode";
            "org.opencontainers.image.description" = "OpenCode AI coding assistant";
          };
        };
      };
      overlays.default = import ./overlay.nix { inherit inputs; };
      # pkgsWithOverlay: nixpkgs with custom overlay applied
      pkgsWithOverlay = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ self.overlays.default ];
      };
      apps.x86_64-linux.colmena = {
        type = "app";
        program = "${colmena.packages.x86_64-linux.colmena}/bin/colmena";
        meta.description = "Colmena multi-host NixOS deployment";
      };
    };
}
