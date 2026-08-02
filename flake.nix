{
  description = "NixOS configuration with Garage and Syncthing storage";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # nixos-unstable as default; override per-package where necessary
    home-manager = {
      url = "git+https://github.com/nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "git+https://github.com/0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    # lsfg-vk - Lossless Scaling Frame Generation on Linux
    lsfg-vk-nix = {
      url = "github:Daaboulex/lsfg-vk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    freebuff-flake = {
      url = "github:reverb256/freebuff-flake";
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

    # Community HDR fork for niri — HDR metadata + hdr { enabled } config.
    # Trade-off: lags behind upstream. Switch programs.niri.package to use it.
    niri-hdr = {
      url = "github:dividebysandwich/niri/hdr-smithay-master";
      flake = false;
    };
    nixcord = {
      url = "git+https://github.com/FlameFlag/nixcord";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    # spicetify-nix - Disabled due to deprecated options in systems dependency
    # Not currently used in configuration
    # spicetify-nix = {
    #   url = "git+https://github.com/Gerg-L/spicetify-nix";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
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
    # cachyos-kernel — transitive dep for cachyos kernel, use git+https for Lix compat
    cachyos-kernel = {
      url = "git+https://github.com/CachyOS/linux-cachyos";
      flake = false;
    };
    # nix-cachyos-kernel — pinned to cc5bc99 (7.1.3 version) because 7.1.4+
    # breaks nvidia-open-595 driver compile (linux/of_gpio.h removed in 6.10+)
    nix-cachyos-kernel.url = "git+https://github.com/xddxdd/nix-cachyos-kernel?rev=cc5bc99baf27245f2644c1fe13f7bac5d3d47865";
    nix-cachyos-kernel.inputs.flake-parts.follows = "flake-parts";
    nix-cachyos-kernel.inputs.cachyos-kernel.follows = "cachyos-kernel";
    # nixpkgs-vfio REMOVED — nixpkgs is now nixos-unstable, so vfio packages
    # (kvmfr, looking-glass-client, qemu_kvm, scream, virtio-win) are available
    # from the main nixpkgs. vfioPkgs is now equivalent to pkgs itself.
    # linux-cachyos override — may not exist in all kernel flake versions, non-fatal if ignored
    # ── Inputs required by common-modules-list.nix (re-added after a drift where
    #    they were dropped from flake.nix but still referenced in the module list) ──
    # NOTE: hermes-agent input REMOVED (issue #334). Hermes is installed via
    # `nix profile install github:NousResearch/hermes-agent` into the user
    # profile; nixos-config no longer builds or manages the hermes-agent package
    # (its importNpmLock offline prefetch of @nous-research/ui is broken).
    # mcp-registry - MCP server registry module
    mcp-registry = {
      url = "github:reverb256/mcp-registry";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # caddy-ingress - Caddy ingress module + caddy-with-modules package
    caddy-ingress = {
      url = "github:reverb256/caddy-ingress";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # gpu-proxy - GPU proxy module
    gpu-proxy = {
      url = "github:reverb256/gpu-proxy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # flake-parts — transitive dep for 6 inputs, use git+https to bypass GitHub API 401
    flake-parts = {
      url = "git+https://github.com/hercules-ci/flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # noctalia REMOVED — upstreamed into nixpkgs-unstable as programs.noctalia
    # + pkgs.noctalia. The flake input is no longer needed.
    # stylix - theming module
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixpkgs-secretspec REMOVED — nixpkgs is now nixos-unstable, so
    # secretspec 0.17.0 with native sops provider is available directly.

    # gitlawb - local option-4 flake: packages + overlay + NixOS module
    gitlawb = {
      url = "path:./pkgs/gitlawb";
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
        overlays = [ (import ./overlays/default.nix { inherit inputs; }) ];
      };

      # Scoped recent-nixpkgs for VFIO/Looking Glass packages only.
      # Reference the flake output's legacyPackages set directly (verified to
      # expose kvmfr / looking-glass-client / OVMFFull / qemu_kvm / scream / virtio-win).
      vfioPkgs = pkgs; # nixpkgs is now unstable — vfioPkgs == pkgs

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
            inherit inputs vfioPkgs;
          };
          modules =
            commonModules
            ++ [
              ./hosts/${hostName}/configuration.nix
            ]
            ++ extraModules;
        };

      # HOST DEFINITIONS - WHOLE-CLUSTER SOURCE OF TRUTH
      # hostName: matches ./hosts/<n>/ and networking.hostName
      # targetHost: colmenua targetHost (IP/hostname for remote, null = local)
      # buildOnTarget: colmneda buildOnTarget (true=build-on-remote, false=build elsewhere)
      # tags: colmneda tag set for selective deploys
      # extraModules: per-host NixOS modules appended after commonModules              # (use this to selectively load desktop-only modules for
              # zephyr/forge while keeping nexus/sentry free of niri/etc)
      # Adding a 5th host = 1 attr here + ./hosts/<n>/configuration.nix +
      #                     + (optionally) 1 entry in `machines` for colmneda.
      #   NOTE: also update ./machines (its keys are colmneda machine entries).

      hosts = {
        zephyr = {
          hostName = "zephyr";
          targetHost = "10.1.1.110";
          buildOnTarget = false; # Nexus dispatcher builds here and pushes to Zephyr
          tags = [
            "control-plane"
            "k8s-master"
            "k8s-node"
            "local"
            "desktop"
          ];
          # Desktop-only sub-tree (AAGL + Stylix + Niri-overlay).
          # Audit F-13 (2026-07-28): extracted from common-modules-list.nix
          # so nexus/forge/sentry skip the eval. The file at
          # modules/desktop/desktop-modules.nix documents the wiring.
          extraModules = [ ./modules/desktop/desktop-modules.nix ];
        };
        nexus = {
          hostName = "nexus";
          targetHost = null; # Nexus dispatcher activates the local controller directly
          buildOnTarget = false; # Nexus dispatcher builds and activates locally
          tags = [
            "storage"
            "k8s-worker"
            "k8s-storage"
            "nvidia-gpu"
            "remote"
          ];
          extraModules = [ ];
        };
        forge = {
          hostName = "forge";
          targetHost = "10.1.1.130";
          buildOnTarget = false; # Nexus dispatcher builds and pushes to Forge
          tags = [
            "gpu"
            "compute"
            "k8s-worker"
            "k8s-gpu-mixed"
            "remote"
          ];
          extraModules = [ ];
        };
        sentry = {
          hostName = "sentry";
          targetHost = "10.1.1.140";
          buildOnTarget = false; # Nexus dispatcher builds and pushes to Sentry
          tags = [
            "monitoring"
            "k8s-worker"
            "k8s-gpu-amd"
            "remote"
          ];
          extraModules = [ ];
        };
      };
    in
    {

      # OUTPUT 1: nixosConfigurations (for local nixos-rebuild)

      nixosConfigurations = builtins.mapAttrs (
        _name: value:
          mkNixosSystem {
            inherit (value) hostName extraModules;
          }
      ) hosts;

      # OUTPUT 2: colmena (raw hive configuration)
      # The `hosts` attrset here is the WHOLE-CLUSTER source of truth.
      # `colmena.nix` derives both `meta.nodeNixpkgs` AND each host's
      # colmenua `meta` from it. No duplicate host declarations needed.

      colmena = import ./colmena.nix {
        inherit inputs self hosts commonModules;
      };

      # OUTPUT 3: colmenaHive (for multi-host deployment)
      # Wraps the raw hive configuration with makeHive for proper schema

      colmenaHive = colmena.lib.makeHive self.outputs.colmena;

      # OUTPUT 4: homeConfigurations
      # Standalone Home Manager activations for j_kro on every cluster host.
      # Uses HM-only modules through modules/home-manager/standalone.nix so this
      # does not pull NixOS-class modules into `home-manager switch`.

      homeConfigurations = builtins.mapAttrs (
        _name: value:
          home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };

            modules = [ ./modules/home-manager/standalone.nix ];
            extraSpecialArgs = { inherit inputs vfioPkgs; hostName = value.hostName; };
          }
      ) hosts;

      # EXISTING OUTPUTS (maintain compatibility)

      packages.x86_64-linux.claude = claude-native.packages.x86_64-linux.claude;
      packages.x86_64-linux.llama-cpp = pkgs.llama-cpp;
      packages.x86_64-linux.secretspec = pkgs.secretspec; # from nixos-unstable
      # CONTAINER IMAGES (for Kubernetes deployment)

      # Claude Code container image for Kubernetes deployment
      # Container images extracted to pkgs/ on 2026-07-29 (audit change 3).
      # /etc/nixos/pkgs/claude-code-image/default.nix — pkgs.callPackage'd.
      # /etc/nixos/pkgs/opencode-image/default.nix — pkgs.callPackage'd.
      packages.x86_64-linux.claude-code-image =
        pkgs.callPackage ./pkgs/claude-code-image { };
      packages.x86_64-linux.opencode-image =
        pkgs.callPackage ./pkgs/opencode-image { };
      packages.x86_64-linux.ai-inference-gateway-image =
        pkgs.callPackage ./pkgs/ai-inference-gateway-image
          { };
      # Requires impure paths - build manually: nix build .#kb-mcp-image --impure
      # packages.x86_64-linux.kb-mcp-image = pkgs.callPackage ./pkgs/kb-mcp-image { };
      overlays.default = import ./overlays/default.nix { inherit inputs; };
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
      # ── FORMATTING GATE ───────────────────────────────────────
      # `nix fmt` -> alejandra (format) across the tree.

    };
}
