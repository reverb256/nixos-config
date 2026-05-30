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
      url = "github:0xc000022070/zen-browser-flake/5bcdfcef664bf62831dcb4b947004d9c5fbf7201";
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
    # claude-native = { # REMOVED - GitHub redirect issue preventing builds
    #   url = "github:ryoppippi/nix-claude-code/6b5a0e9bee689f0f21ad9f19c19a359ebe0593e0";
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
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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
      url = "github:cynicsketch/nix-mineral/";
    };

    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "";
      inputs.home-manager.follows = "";
    };
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel/release";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    easykubenix.url = "github:Lillecarl/easykubenix/88a025fc04889f25b702f79030c6220c3ec48f9b";

    nix-csi.url = "github:Lillecarl/nix-csi";
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ═══════════════════════════════════════════════════════════════════
    # EXTRACTED PROJECTS — Migration in progress (see EXTRACTION-PLAN.md)
    # Uncomment each input after verifying the project builds independently.
    # When all verified, remove the original files from nixos-config.
    # ═══════════════════════════════════════════════════════════════════

    ai-gateway = {
      url = "github:reverb256/ai-inference-gateway/96497a4227147d96d7ccc721ab293302a61fe13d";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    knowledge-fabric = {
      url = "github:reverb256/knowledge-fabric";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    compute-market = {
      url = "github:reverb256/compute-market/02eb54874adf8a0887a4878a99d33274af9d5404";
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
    astral-key = {
      url = "github:reverb256/astral-key";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llama-turboquant = {
      url = "path:/data/projects/own/llama-cpp-turboquant";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vllm = {
      url = "path:/data/projects/own/vllm";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # NOTE: astral-key has nixos-module.nix for systemd service — can be imported in host configs
    dream2nix = {
      url = "github:nix-community/dream2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    process-compose = {
      url = "github:F1bonacc1/process-compose";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-fast-build = {
      url = "github:Mic92/nix-fast-build";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    bun2nix = {
      url = "github:nix-community/bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # WSL — NixOS on Windows Subsystem for Linux (krash3)
    NixOS-WSL = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ── Newly extracted project flakes ───────────────────────
    # hermes-workspace and hermes-webui archived (2026-05-16)
    maplespike = {
      url = "path:/data/projects/own/maplespike";
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

  # Slim module set for WSL/remote hosts — no desktop/GPU/cluster modules
  slimModules = [
    inputs.home-manager.nixosModules.home-manager
    inputs.agenix.nixosModules.default
    ./modules/default.nix
    {
      nixpkgs.overlays = [ self.overlays.default ];
      age.identityPaths = [
        "/persistent/etc/age/key.txt"
        "/etc/nixos/.age/key.txt"
        "/etc/age/key.txt"
        "/home/j_kro/.age/key.txt"
      ];
    }
  ];

  mkNixosSystem = {
    hostName,
    extraModules ? [],
    k8sManifest ? null,
    modules ? commonModules,
  }:
      nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
        };
        modules =
          modules
          ++ [
            ./hosts/${hostName}/configuration.nix
          ]
          ++ extraModules
          ++ nixpkgs.lib.optional (k8sManifest != null) {
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
        # Split manifests - nexus runs monitoring, ai-inference, llama-servers
        k8sManifest = self.kubernetes.monitoring.manifestYAMLFile;
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
      k8sManifest = null; # No K8s manifests
      modules = slimModules; # WSL — no desktop/GPU/cluster
    };
    };
  in {
    checks.x86_64-linux = {};

  nixosConfigurations =
  (builtins.mapAttrs (
    _name: value: mkNixosSystem {
      inherit (value) hostName;
      k8sManifest = value.k8sManifest or null;
      modules = value.modules or commonModules;
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
        usb-rescue = nixpkgs.lib.nixosSystem {
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

    # packages.x86_64-linux.claude = claude-native.packages.x86_64-linux.claude; # REMOVED - GitHub redirect issue
    packages.x86_64-linux.llama-cpp = pkgsWithOverlay.llama-cpp;
    packages.x86_64-linux.llama-cpp-ik = pkgsWithOverlay.llama-cpp-ik;
    packages.x86_64-linux.llama-cpp-turboquant = pkgsWithOverlay.llama-cpp-turboquant;
    # vllm-turboquant-env: Nix store path for nix-csi scratch containers
    packages.x86_64-linux.vllm-turboquant-env = inputs.vllm.packages.x86_64-linux.vllm-turboquant-env;
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
    packages.x86_64-linux.maplespike-mcp-image = pkgsWithOverlay.maplespike-mcp-image;
    packages.x86_64-linux.maplespike-api-image = pkgsWithOverlay.maplespike-api-image;
  packages.x86_64-linux = {
    # ai-inference-gateway-image = lib.mkIf (inputs ? ai-gateway) inputs.ai-gateway.packages.x86_64-linux.container; # migrated from local pkgs/
    inherit (pkgsWithOverlay)
      maplespike-ingest-image
      maplespike-engine-image;
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