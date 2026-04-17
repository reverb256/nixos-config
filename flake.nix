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
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    easykubenix.url = "github:Lillecarl/easykubenix";

    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ═══════════════════════════════════════════════════════════════════
    # EXTRACTED PROJECTS — Migration in progress (see EXTRACTION-PLAN.md)
    # Uncomment each input after verifying the project builds independently.
    # When all verified, remove the original files from nixos-config.
    # ═══════════════════════════════════════════════════════════════════

    # ai-gateway = {
    #   url = "path:/data/projects/own/ai-inference-gateway";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    # knowledge-fabric = {
    #   url = "path:/data/projects/own/knowledge-fabric";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    # llama-turboquant = {
    #   url = "path:/data/projects/own/llama-cpp-turboquant";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    # compute-market = {
    #   url = "path:/data/projects/own/compute-market";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    # mcp-registry = {
    #   url = "path:/data/projects/own/mcp-registry";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    # caddy-ingress = {
    #   url = "path:/data/projects/own/caddy-ingress";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    # gpu-proxy = {
    #   url = "path:/data/projects/own/gpu-proxy";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
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
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        config.cudaSupport = true;
      };
      pkgsWithOverlay = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        config.cudaSupport = true;
        overlays = [ (import ./overlay.nix) ];
      };


      commonModules = import ./common-modules-list.nix {
        inherit inputs self;
      };


      mkNixosSystem =
        {
          hostName,
          extraModules ? [ ],
        }:
        nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs;
            k8sManifestPackage = self.packages.x86_64-linux.k8s-manifests;
          };
          modules =
            commonModules
            ++ [
              ./hosts/${hostName}/configuration.nix
            ]
            ++ extraModules;
        };


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


      nixosConfigurations = builtins.mapAttrs (
        _name: value: mkNixosSystem { inherit (value) hostName; }
      ) hosts;


      colmena = import ./colmena.nix {
        inherit inputs self;
        inherit hosts;
      };


      colmenaHive = colmena.lib.makeHive self.outputs.colmena;


      packages.x86_64-linux.claude = claude-native.packages.x86_64-linux.claude;
      packages.x86_64-linux.llama-cpp = pkgsWithOverlay.llama-cpp;
      packages.x86_64-linux.caddy-with-modules = pkgsWithOverlay.caddy-with-modules;
      packages.x86_64-linux.caddy-ingress-image = pkgs.callPackage ./pkgs/caddy-ingress-image {
        inherit (pkgsWithOverlay) caddy-with-modules;
      };


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
            "3333/tcp" = { };
            "8081/tcp" = { };
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
            "4068/tcp" = { };
          };
          Env = [
            "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
            "PATH=/bin"
            "GPU_MAX_HEAP_SIZE=100"
            "GPU_MAX_ALLOC_PERCENT=100"
          ];
        };
      };
      packages.x86_64-linux.lolminer-amd-image =
        let
          glibc = pkgs.glibc;
          lolminerPkg = pkgsWithOverlay.lolminer;
          rootFs = pkgsWithOverlay.runCommand "lolminer-amd-root" { } ''
            mkdir -p $out/bin $out/etc $out/lib $out/lib64 $out/tmp $out/run/opengl-driver/lib $out/etc/OpenCL/vendors
            cp ${lolminerPkg}/bin/.lolMiner-wrapped $out/bin/.lolMiner-wrapped
            chmod +x $out/bin/.lolMiner-wrapped
            echo '#! /bin/sh -e' > $out/bin/lolMiner
            echo 'LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$LD_LIBRARY_PATH:' >> $out/bin/lolMiner
            echo 'LD_LIBRARY_PATH=/lib:$LD_LIBRARY_PATH' >> $out/bin/lolMiner
            echo 'export LD_LIBRARY_PATH' >> $out/bin/lolMiner
            echo 'exec /bin/.lolMiner-wrapped "$@"' >> $out/bin/lolMiner
            chmod +x $out/bin/lolMiner
            for pkg in ${pkgsWithOverlay.bash} ${pkgsWithOverlay.coreutils}; do
              if [ -d "$pkg/bin" ]; then
                for bin in $pkg/bin/*; do
                  [ -e "$bin" ] && ln -sf "$bin" $out/bin/
                done
              fi
              if [ -d "$pkg/lib" ]; then
                cp -rL "$pkg/lib"/* $out/lib/ 2>/dev/null || true
              fi
            done
            mkdir -p $out/etc/ssl/certs
            ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt $out/etc/ssl/certs/
            for pkg in ${pkgs.rocmPackages.clr} ${pkgs.rocmPackages.clr.icd} ${pkgs.mesa.opencl}; do
              if [ -d "$pkg/lib" ]; then
                cp -rL "$pkg/lib"/* $out/lib/ 2>/dev/null || true
              fi
              if [ -d "$pkg/lib" ]; then
                cp -rL "$pkg/lib"/* $out/run/opengl-driver/lib/ 2>/dev/null || true
              fi
              if [ -d "$pkg/etc" ]; then
                cp -r $pkg/etc/* $out/etc/ 2>/dev/null || true
              fi
            done
            rm -f $out/etc/OpenCL/vendors/rusticl.icd
            cp -rL ${glibc}/lib/* $out/lib/ 2>/dev/null || true
            mkdir -p $out/lib64
            cp -rL ${glibc}/lib/* $out/lib64/ 2>/dev/null || true
            rm -f $out/etc/OpenCL/vendors/amdocl64.icd
            echo "/lib/libamdocl64.so" > $out/etc/OpenCL/vendors/amdocl64.icd
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
              "4069/tcp" = { };
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
      packages.x86_64-linux.xmrig-nixos-image = pkgs.dockerTools.buildLayeredImage {
        name = "xmrig-nixos";
        tag = "latest";
        contents = [
          pkgs.xmrig
          pkgs.bash
          pkgs.coreutils
        ];
        config = {
          Entrypoint = [ "${pkgs.xmrig}/bin/xmrig" ];
          Env = [ "PATH=/bin" ];
          Labels = {
            "description" = "XMRig NixOS container with GLIBC compatibility";
          };
        };
      };
      packages.x86_64-linux.xmrig-alpine-image = pkgs.callPackage ./pkgs/xmrig-alpine-image { };
      packages.x86_64-linux.xmrig-proxy-alpine-image =
        pkgs.callPackage ./pkgs/xmrig-proxy-alpine-image
          { };
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
      overlays.default = import ./overlay.nix;
      pkgsWithOverlay = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        config.cudaSupport = true;
        overlays = [ self.overlays.default ];
      };
      kubernetes = import ./kubernetes { inherit pkgs pkgsWithOverlay inputs; };

      packages.x86_64-linux.k8s-manifests = self.kubernetes.manifestYAMLFile;

      apps.x86_64-linux.k8s-validate = {
        type = "app";
        program = "${self.kubernetes.validationScript}/bin/kubeval";
        meta.description = "Validate K8s manifests against ephemeral apiserver";
      };

      apps.x86_64-linux.k8s-deploy = {
        type = "app";
        program = "${self.kubernetes.deploymentScript}/bin/kubenixDeploy";
        meta.description = "Deploy K8s manifests via kluctl";
      };

      apps.x86_64-linux.colmena = {
        type = "app";
        program = "${colmena.packages.x86_64-linux.colmena}/bin/colmena";
        meta.description = "Colmena multi-host NixOS deployment";
      };
    };
}
