{
  description = "NixOS configuration with Garage and Syncthing storage";
  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
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

    noctalia = {
      url = "github:noctalia-dev/noctalia/cachix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-native = {
      url = "github:ryoppippi/nix-claude-code";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    scopebuddy = {
      url = "github:OpenGamingCollective/ScopeBuddy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcord = {
      url = "github:FlameFlag/nixcord";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # System hardening (Phase 0: Security Baseline)
    # https://github.com/cynicsketch/nix-mineral
    # Phase 3: MicroVM isolation (Qubes-like compartmentalization)
    # https://github.com/microvm-nix/microvm.nix
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-mineral = {
      url = "github:cynicsketch/nix-mineral";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "";
      inputs.home-manager.follows = "";
    };
    preservation = {
      url = "path:/etc/nixos/lib/preservation";
    };
    niri = {
      # Pinned to commit that exports lib.niri.actions with spawn/spawn-sh/focus-window-previous
      # (replaces b5f81cf03… which lacked focus-window-previous and broke niri-config binds).
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    easykubenix.url = "github:Lillecarl/easykubenix";

    nix-csi = {
      url = "github:Lillecarl/nix-csi";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ═══════════════════════════════════════════════════════════════════
    # EXTRACTED PROJECTS — Migration in progress (see EXTRACTION-PLAN.md)
    # Uncomment each input after verifying the project builds independently.
    # When all verified, remove the original files from nixos-config.
    # ═══════════════════════════════════════════════════════════════════

    ai-gateway = {
      url = "github:reverb256/ai-inference-gateway";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    compute-market = {
      url = "github:reverb256/compute-market";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mcp-registry = {
      url = "github:reverb256/mcp-registry";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    caddy-ingress = {
      url = "github:reverb256/caddy-ingress";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gpu-proxy = {
      url = "github:reverb256/gpu-proxy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # mining-infra removed - only exists on zephyr at /data/projects/infra/mining-infra
    llama-turboquant = {
      url = "github:reverb256/llama-cpp-turboquant";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # vllm = {
    #   url = "path:/home/j_kro/Projects/vllm";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    bun2nix = {
      url = "github:nix-community/bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ── Newly extracted project flakes ───────────────────────
    # hermes-workspace and hermes-webui archived (2026-05-16)
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    home-manager,
    aagl,
    nur,
    sops-nix,
    nix-mineral,
    colmena,
    pre-commit-hooks,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    pkgsWithOverlay = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      config.cudaSupport = true;
      overlays = [
        inputs.bun2nix.overlays.default
        ((import ./overlay.nix) {inherit inputs;})
      ];
    };

    commonModules = import ./common-modules-list.nix {
      inherit inputs self;
    };

    mkNixosSystem = {
      hostName,
      extraModules ? [],
      k8sManifest ? null,
      modules ? commonModules,
      nixpkgsInput ? nixpkgs,
    }:
      nixpkgsInput.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
        };
        modules =
          modules
          ++ [
            ./hosts/${hostName}/configuration.nix
          ]
          ++ extraModules
          ++ nixpkgsInput.lib.optional (k8sManifest != null) {
            services.k8s-nix-deploy.enable = true;
            services.k8s-nix-deploy.manifestPackage = k8sManifest;
          };
      };

    hosts = {
      zephyr = {
        hostName = "zephyr";
        # Split manifests to avoid eval bottleneck
        k8sManifest = self.kubernetes.small.manifestYAMLFile;
      };
      nexus = {
        hostName = "nexus";
        # Split manifests - nexus runs monitoring, ai-inference, llama-servers, kubevirt
        k8sManifest = self.kubernetes.kubevirt.manifestYAMLFile;
      };
      forge = {
        hostName = "forge";
        # Forge runs mining workloads
        k8sManifest = self.kubernetes.mining.manifestYAMLFile;
      };
      sentry = {
        hostName = "sentry";
        k8sManifest = self.kubernetes.small.manifestYAMLFile;
      };
      krash3 = {
        hostName = "krash3";
        k8sManifest = null;
        modules = (import ./krash3-common-modules.nix { inherit inputs self; });
      };
  };
  in {
    checks.x86_64-linux = {};

    nixosConfigurations =
      (builtins.mapAttrs (
          _name: value:
            mkNixosSystem {
              inherit (value) hostName;
              k8sManifest = value.k8sManifest or null;
              modules = value.modules or commonModules;
              nixpkgsInput = value.nixpkgsInput or nixpkgs;
            }
        )
        hosts)
      // {
        # Phase 3: MicroVM configurations (not regular hosts, not managed by Colmena)
        ci-test = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [./hosts/ci-test/configuration.nix];
          specialArgs = {inherit inputs;};
        };
        # Rescue USB — standalone live ISO (no mining/gaming/K8s)
        usb = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {inherit inputs;};
          modules = [./hosts/usb/configuration.nix];
        };
      };

    colmena = import ./colmena.nix {
      inherit inputs self;
      inherit hosts;
    };

    colmenaHive = colmena.lib.makeHive self.outputs.colmena;

    packages.x86_64-linux.llama-cpp = pkgsWithOverlay.llama-cpp;
    packages.x86_64-linux.llama-cpp-ik = pkgsWithOverlay.llama-cpp-ik;
    #     packages.x86_64-linux.llama-cpp-turboquant = pkgsWithOverlay.llama-cpp-turboquant;
    # vllm-turboquant-env: Nix store path for nix-csi scratch containers
    #     packages.x86_64-linux.vllm-turboquant-env = inputs.vllm.packages.x86_64-linux.vllm-turboquant-env;
    packages.x86_64-linux.caddy-with-modules = inputs.caddy-ingress.packages.x86_64-linux.caddy-with-modules;
    packages.x86_64-linux.caddy-ingress-image = inputs.caddy-ingress.packages.x86_64-linux.caddy-ingress-image;
    packages.x86_64-linux.hermes-chat = pkgsWithOverlay.hermes-chat;
    packages.x86_64-linux.privacy-filter = pkgsWithOverlay.privacy-filter;
    packages.x86_64-linux.kubernetes-mcp-server = pkgs.callPackage ./packages/kubernetes-mcp-server.nix {};
    packages.x86_64-linux.nixos-cluster-mcp = pkgs.callPackage ./packages/nixos-cluster-mcp {};
    packages.x86_64-linux.luce-dflash = pkgs.callPackage ./packages/luce-dflash.nix {};

    packages.x86_64-linux.xmrig-proxy-image = pkgsWithOverlay.dockerTools.buildImage {
      name = "xmrig-proxy";
      tag = "nixos-6.24.0";
      copyToRoot = pkgsWithOverlay.buildEnv {
        name = "xmrig-proxy-root";
        paths = [
          pkgsWithOverlay.xmrig-proxy
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
        Entrypoint = ["/bin/xmrig-proxy"];
        Cmd = [
          "--config=/etc/xmrig-proxy/config.json"
          "--no-color"
        ];
        ExposedPorts = {
          "3333/tcp" = {};
          "8081/tcp" = {};
        };
        Env = [
          "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
          "PATH=/bin"
        ];
      };
    };

    packages.x86_64-linux.xmrig-nixos-image = inputs.compute-market.packages.x86_64-linux.xmrig-nixos-image; # migrated
    packages.x86_64-linux.xmrig-alpine-image = inputs.compute-market.packages.x86_64-linux.xmrig-alpine-image; # migrated
    packages.x86_64-linux.xmrig-proxy-alpine-image = inputs.compute-market.packages.x86_64-linux.xmrig-proxy-alpine-image; # migrated
    packages.x86_64-linux.claude-code-image = pkgsWithOverlay.claude-code-image; # extracted to packages/claude-code-image.nix
    # packages.x86_64-linux.ai-inference-gateway-image = inputs.ai-gateway.packages.x86_64-linux.container; # migrated from local pkgs/ - REMOVED
    packages.x86_64-linux.opencode-image = pkgsWithOverlay.opencode-image;
    #     packages.x86_64-linux.maplespike-mcp-image = pkgsWithOverlay.maplespike-mcp-image;
    #     packages.x86_64-linux.maplespike-api-image = pkgsWithOverlay.maplespike-api-image;
    packages.x86_64-linux = {
      # ai-inference-gateway-image = lib.mkIf (inputs ? ai-gateway) inputs.ai-gateway.packages.x86_64-linux.container; # migrated from local pkgs/
      inherit
        (pkgsWithOverlay)
        #         maplespike-ingest-image
        #         maplespike-engine-image
        ;

      # ── KubeVirt guest disk for the "nexus-de" VM (4K TV on the 3060 Ti) ──
      #    Produces a qcow2 disk image. After build, upload it as the VM's
      #    DataVolume (see images/nexus-de-guest.nix header for the command).
      #    Module imports are resolved inside images/nexus-de-guest.nix via
      #    `self + "/..."` absolute paths (preserves the modules' own relative
      #    imports like peakminer's ../pkgs/peakminer.nix).
      nexusDeGuest = inputs.nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        specialArgs = { inherit inputs self; peakminerPkg = pkgsWithOverlay.peakminer; };
        modules = [
          ./images/nexus-de-guest.nix
        ];
      };
    };

    # hermes-workspace-image and hermes-webui-image archived (2026-05-16)
    overlays.default = (import ./overlay.nix) {inherit inputs;};
    kubernetes = import ./kubernetes {
      lib = inputs.nixpkgs.lib;
      inherit pkgs pkgsWithOverlay inputs;
    };

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

    # ── Phase 5: Unified deployment pipeline apps ───────────────────────────

    apps.x86_64-linux.deploy = {
      type = "app";
      program = toString (pkgs.writeShellScriptBin "deploy" ''
        exec ${self}/scripts/deploy.sh "$@"
      '');
      meta.description = "Unified deployment: validate + colmena + nix copy + k8s apply";
    };

    apps.x86_64-linux.rollback = {
      type = "app";
      program = toString (pkgs.writeShellScriptBin "rollback" ''
        exec ${self}/scripts/rollback.sh "$@"
      '');
      meta.description = "Unified rollback for OS and K8s";
    };

    apps.x86_64-linux.check = {
      type = "app";
      program = toString (pkgs.writeShellScriptBin "check" ''
        exec ${self}/scripts/check.sh "$@"
      '');
      meta.description = "Run all validations: flake check, colmena build, k8s dry-run, connectivity";
    };
  };
}