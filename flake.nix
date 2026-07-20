{
  description = "NixOS configuration with Garage and Syncthing storage";
  inputs = {
    nixpkgs.url = "tarball+https://codeload.github.com/NixOS/nixpkgs/tar.gz/9ae611a455b90cf061d8f332b977e387bda8e1ca"; # pinned: predates nixos-unstable pkgs-fixedPoint recursion regression
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
    # nixpkgs-xr - Bleeding-edge XR/VR packages (WiVRn, Monado, libsurvive, xrizer, etc.)
    # Provides binary cache at nix-community.cachix.org
    nixpkgs-xr = {
      url = "github:nix-community/nixpkgs-xr";
    };
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
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Colmena - Multi-host deployment
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Niri - Scrollable-tiling Wayland compositor
    # Provides: programs.niri NixOS module, niri-unstable overlay, home-manager module
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # llm-agents.nix - Nix packages for AI coding agents (Droid, etc.)
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # CachyOS kernel - Performance-optimized kernel for gaming/desktop (Zephyr only)
    # Provides: linux-cachyos-latest-x86_64-v3, sched_ext support, BORE scheduler
    # Binary cache: attic.xuyh0120.win/lantian (no local compilation needed)
    # Do NOT follow nixpkgs — uses its own pinned nixos-unstable-small for kernel builds
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    # ── Inputs required by common-modules-list.nix (re-added after a drift where
    #    they were dropped from flake.nix but still referenced in the module list) ──
    # hermes-agent - Hermes Agent NixOS module + packages
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
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
    # compute-market - xmrig/compute market images (local tarball)
    compute-market = {
      url = "tarball+file:///tmp/compute-market.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # gpu-proxy - GPU proxy module (local tarball)
    gpu-proxy = {
      url = "tarball+file:///tmp/gpu-proxy.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # noctalia - brightness daemon for NixOS
    noctalia = {
      url = "github:noctalia-dev/noctalia/e2f529a4a39ce924c36f6633ded1ce0a88312ec2";
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
      # Used for package outputs that need custom packages (lolminer, xmrig, etc.)
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
          Entrypoint = [ "/bin/xmrig-proxy" ];
          Cmd = [
            "--config=/etc/xmrig-proxy/config.json"
            "--no-color"
          ];
          ExposedPorts = {
            "3333/tcp" = { }; # Stratum port
            "8081/tcp" = { }; # API port
          };
          Env = [
            "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
            "PATH=/bin"
          ];
        };
      };
      packages.x86_64-linux.lolminer-image = pkgsWithOverlay.dockerTools.buildImage {
        name = "lolminer";
        tag = "1.98a-nixos";
        copyToRoot = pkgsWithOverlay.buildEnv {
          name = "lolminer-root";
          paths = [
            pkgsWithOverlay.lolminer
            pkgsWithOverlay.bash
            pkgsWithOverlay.coreutils
            pkgsWithOverlay.cacert
          ];
          pathsToLink = [
            "/bin"
            "/etc"
            "/lib"
          ];
        };
        config = {
          Entrypoint = [ "/bin/lolMiner" ];
          Cmd = [ ];
          ExposedPorts = {
            "4068/tcp" = { }; # API port
          };
          Env = [
            "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
            "PATH=/bin"
            "GPU_MAX_HEAP_SIZE=100"
            "GPU_MAX_ALLOC_PERCENT=100"
          ];
        };
      };
      # NixOS-based lolMiner image with AMD OpenCL/ROCm support
      # Uses steam-run for FHS compatibility and proper library resolution
      packages.x86_64-linux.lolminer-amd-image =
        let
          # Get glibc directly from nixpkgs (same version as host)
          glibc = pkgs.glibc;
          # Use the full lolMiner package (includes wrapper with LD_LIBRARY_PATH setup)
          lolminerPkg = pkgsWithOverlay.lolminer;
          # Custom root filesystem with all required libraries
          # NO steam-run - lolMiner wrapper already handles LD_LIBRARY_PATH
          rootFs = pkgsWithOverlay.runCommand "lolminer-amd-root" { } ''
            mkdir -p $out/bin $out/etc $out/lib $out/lib64 $out/tmp $out/run/opengl-driver/lib $out/etc/OpenCL/vendors
            # Copy lolMiner wrapper and binary
            # The wrapper has hardcoded Nix paths, so we need to create our own
            cp ${lolminerPkg}/bin/.lolMiner-wrapped $out/bin/.lolMiner-wrapped
            chmod +x $out/bin/.lolMiner-wrapped
            # Create wrapper that uses relative paths (works in container)
            # Libraries are in /lib, not /run/opengl-driver/lib (that dir is empty)
            echo '#! /bin/sh -e' > $out/bin/lolMiner
            echo 'LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$LD_LIBRARY_PATH:' >> $out/bin/lolMiner
            echo 'LD_LIBRARY_PATH=/lib:$LD_LIBRARY_PATH' >> $out/bin/lolMiner
            echo 'export LD_LIBRARY_PATH' >> $out/bin/lolMiner
            echo 'exec /bin/.lolMiner-wrapped "$@"' >> $out/bin/lolMiner
            chmod +x $out/bin/lolMiner
            # Copy bash, coreutils binaries (symlinks ok for binaries)
            for pkg in ${pkgsWithOverlay.bash} ${pkgsWithOverlay.coreutils}; do
              if [ -d "$pkg/bin" ]; then
                for bin in $pkg/bin/*; do
                  [ -e "$bin" ] && ln -sf "$bin" $out/bin/
                done
              fi
              # Recursively copy entire lib directories to preserve symlink structure
              if [ -d "$pkg/lib" ]; then
                cp -rL "$pkg/lib"/* $out/lib/ 2>/dev/null || true
              fi
            done
            # Copy certificates
            mkdir -p $out/etc/ssl/certs
            ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt $out/etc/ssl/certs/
            # Copy ROCm/OpenCL libraries - recursively copy entire directories
            for pkg in ${pkgs.rocmPackages.clr} ${pkgs.rocmPackages.clr.icd} ${pkgs.mesa.opencl}; do
              # Recursively copy lib directory (preserves all symlinks and their targets)
              if [ -d "$pkg/lib" ]; then
                cp -rL "$pkg/lib"/* $out/lib/ 2>/dev/null || true
              fi
              # Also copy to /run/opengl-driver/lib for lolMiner wrapper
              if [ -d "$pkg/lib" ]; then
                cp -rL "$pkg/lib"/* $out/run/opengl-driver/lib/ 2>/dev/null || true
              fi
              if [ -d "$pkg/etc" ]; then
                cp -r $pkg/etc/* $out/etc/ 2>/dev/null || true
              fi
            done
            # Remove rusticl ICD file that points to non-existent Nix store path
            rm -f $out/etc/OpenCL/vendors/rusticl.icd
            # Copy glibc libraries - recursively copy entire directory
            cp -rL ${glibc}/lib/* $out/lib/ 2>/dev/null || true
            # Also create in lib64 for the interpreter
            mkdir -p $out/lib64
            cp -rL ${glibc}/lib/* $out/lib64/ 2>/dev/null || true
            # Create OpenCL ICD file pointing to the container library path
            # The library will be at /lib/libamdocl64.so when container runs
            # NOT at the build-time $out/lib path
            # First remove the read-only ICD file copied from ROCm package (line 347)
            rm -f $out/etc/OpenCL/vendors/amdocl64.icd
            echo "/lib/libamdocl64.so" > $out/etc/OpenCL/vendors/amdocl64.icd
            # Create lib64 directory and symlinks (not a symlink to lib)
            # The binary needs /lib64/ld-linux-x86-64.so.2
            # We already created it above, but we need to ensure it's not overwritten
            # Note: lib64 is now a real directory, not a symlink to lib
          '';
        in
        pkgsWithOverlay.dockerTools.buildImage {
          name = "lolminer-amd";
          tag = "1.98a-nixos";
          copyToRoot = rootFs;
          config = {
            Entrypoint = [ "/bin/lolMiner" ];
            Cmd = [ ];
            ExposedPorts = {
              "4069/tcp" = { }; # AMD API port
            };
            Env = [
              "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
              "OCL_ICD_VENDORS=/etc/OpenCL/vendors"
              "LD_LIBRARY_PATH=/lib"
              "GPU_MAX_HEAP_SIZE=100"
              "GPU_MAX_ALLOC_PERCENT=100"
            ];
            Labels = {
              "version" = "1.98a";
              "description" = "lolMiner NixOS container with AMD OpenCL support";
            };
          };
        };
      # NixOS-based xmrig container image
      # Uses host GLIBC for compatibility (avoids GLIBC_2.29 issue)
      packages.x86_64-linux.xmrig-nixos-image = pkgs.dockerTools.buildLayeredImage {
        name = "xmrig-nixos";
        tag = "latest";
        contents = [
          pkgs.xmrig
          pkgs.bash
          pkgs.coreutils
        ];
        config = {
          # Don't set Cmd - let Kubernetes provide command/args
          Entrypoint = [ "${pkgs.xmrig}/bin/xmrig" ];
          Env = [ "PATH=/bin" ];
          Labels = {
            "description" = "XMRig NixOS container with GLIBC compatibility";
          };
        };
      };
      # Alpine-based XMRig — static binary, ~20MB vs ~81MB for xmrig-nixos
      packages.x86_64-linux.xmrig-alpine-image = pkgs.callPackage ./pkgs/xmrig-alpine-image { };
      # Alpine-based XMRig Proxy — static binary relay
      packages.x86_64-linux.xmrig-proxy-alpine-image =
        pkgs.callPackage ./pkgs/xmrig-proxy-alpine-image
          { };
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
      # Used for package outputs that need custom packages (lolminer, xmrig, etc.)
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
