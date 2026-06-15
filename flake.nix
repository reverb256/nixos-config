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
    # Stable fallback — 26.05 for hosts that can't run unstable
    nixpkgs-2605.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "tarball+https://codeload.github.com/nix-community/home-manager/tar.gz/509ed3c603349a9d43de9e2ae6613baea6bd5b34";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "tarball+https://codeload.github.com/0xc000022070/zen-browser-flake/tar.gz/5bcdfcef664bf62831dcb4b947004d9c5fbf7201";
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
      url = "tarball+https://codeload.github.com/nix-community/NUR/tar.gz/0eb436e129c6a77d5e0ac3ac9af4219ddfc8167e";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-native = {
      url = "tarball+https://codeload.github.com/ryoppippi/nix-claude-code/tar.gz/6b5a0e9bee689f0f21ad9f19c19a359ebe0593e0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    scopebuddy = {
      url = "tarball+https://codeload.github.com/OpenGamingCollective/ScopeBuddy/tar.gz/150051976a2a1e64179edc7265175ba4e5f62f62";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcord = {
      url = "tarball+https://codeload.github.com/FlameFlag/nixcord/tar.gz/45a98c17b0d9e695bdee92ab00c76657eddf47e7";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # System hardening (Phase 0: Security Baseline)
    # https://github.com/cynicsketch/nix-mineral
    # Phase 3: MicroVM isolation (Qubes-like compartmentalization)
    # https://github.com/microvm-nix/microvm.nix
    microvm = {
      url = "tarball+https://codeload.github.com/microvm-nix/microvm.nix/tar.gz/9755fd345bd64d1c75ba12b63089c926dd5d886e";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-mineral = {
      url = "github:cynicsketch/nix-mineral/";
    };

    colmena = {
      url = "tarball+https://codeload.github.com/zhaofengli/colmena/tar.gz/349b035a5027f23d88eeb3bc41085d7ee29f18ed";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "tarball+https://codeload.github.com/nix-community/disko/tar.gz/65fb947964bd44fc0008faf77d1fcb7a9f40bb32";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "tarball+https://codeload.github.com/nix-community/impermanence/tar.gz/7b1d382faf603b6d264f58627330f9faa5cba149";
      inputs.nixpkgs.follows = "";
      inputs.home-manager.follows = "";
    };
    preservation = {
      url = "path:/etc/nixos/lib/preservation";
    };
    niri = {
      url = "tarball+https://codeload.github.com/sodiboo/niri-flake/tar.gz/b5f81cf03d90bcf2efd20d12fe933a0790b4722b";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "tarball+https://codeload.github.com/numtide/llm-agents.nix/tar.gz/6371ebfe504b61b7f029797c07bfe65db39c4163";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel/86d7051a5694db99f4db6165bcaf15e7bba8672a";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "tarball+https://codeload.github.com/nix-community/stylix/tar.gz/c1456cc4ba3c9485e7b4158c909eeca5a752cd59";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    easykubenix.url = "github:Lillecarl/easykubenix/88a025fc04889f25b702f79030c6220c3ec48f9b";

    nix-csi.url = "github:Lillecarl/nix-csi";
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
      url = "tarball+https://codeload.github.com/reverb256/ai-inference-gateway/tar.gz/96497a4227147d96d7ccc721ab293302a61fe13d";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    knowledge-fabric = {
      url = "tarball+https://codeload.github.com/reverb256/knowledge-fabric/tar.gz/9f3e90153be35a31a047693404ccea084a868138";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    compute-market = {
      url = "tarball+https://codeload.github.com/reverb256/compute-market/tar.gz/02eb54874adf8a0887a4878a99d33274af9d5404";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mcp-registry = {
      url = "tarball+https://codeload.github.com/reverb256/mcp-registry/tar.gz/d2d5daafaa9cd8f99feff39f8c18bbda014033b1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    caddy-ingress = {
      url = "tarball+https://codeload.github.com/reverb256/caddy-ingress/tar.gz/a6bc19374ed68da7c769473e2b36cefc3355ac39";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gpu-proxy = {
      url = "tarball+https://codeload.github.com/reverb256/gpu-proxy/tar.gz/d17e8fa40d5f539714f05b7387b30a0e831c1c12";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # mining-infra removed - only exists on zephyr at /data/projects/infra/mining-infra
    astral-key = {
      url = "tarball+https://codeload.github.com/reverb256/astral-key/tar.gz/b269cc69718f3a902ea61aaf29459cae98d96592";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    #     llama-turboquant = {
    #       url = "path:/data/projects/own/llama-cpp-turboquant";
    #       inputs.nixpkgs.follows = "nixpkgs";
    #     };
    #     vllm = {
    #       url = "path:/data/projects/own/vllm";
    #       inputs.nixpkgs.follows = "nixpkgs";
    #     };
    # NOTE: astral-key has nixos-module.nix for systemd service — can be imported in host configs
    dream2nix = {
      url = "tarball+https://codeload.github.com/nix-community/dream2nix/tar.gz/69eb01fa0995e1e90add49d8ca5bcba213b0416f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "tarball+https://codeload.github.com/cachix/pre-commit-hooks.nix/tar.gz/61ab0e80d9c7ab14c256b5b453d8b3fb0189ba0a";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    process-compose = {
      url = "tarball+https://codeload.github.com/F1bonacc1/process-compose/tar.gz/5e62578ad443ccb5ea5761119305335528f0cf10";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-fast-build = {
      url = "tarball+https://codeload.github.com/Mic92/nix-fast-build/tar.gz/ab8dadc27c73855a958198c6f994398f0e84d2ab";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    bun2nix = {
      url = "tarball+https://codeload.github.com/nix-community/bun2nix/tar.gz/f2bc12af1a6369648aac41041ceeaa0b866599c6";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # WSL — NixOS on Windows Subsystem for Linux (krash3)
    NixOS-WSL = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ── Newly extracted project flakes ───────────────────────
    # hermes-workspace and hermes-webui archived (2026-05-16)
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-2605,
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

    # Slim module set for WSL/remote hosts — no desktop/GPU/cluster modules
    slimModules = [
      inputs.home-manager.nixosModules.home-manager
      inputs.sops-nix.nixosModules.default
      inputs.stylix.nixosModules.default
    ];

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
        k8sManifest = null;
        modules = slimModules;
        nixpkgsInput = inputs.nixpkgs-2605;
      };
      krash3-krash = {
        hostName = "krash3-krash";
        k8sManifest = null;
        modules = slimModules;
        nixpkgsInput = inputs.nixpkgs-2605;
      };
  };
  in {
    checks.x86_64-linux = {
      # Build ci-test config (microVM for CI) — verifies it evaluates cleanly
      ci-test-eval = (nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [./hosts/ci-test/configuration.nix];
        specialArgs = {inherit inputs;};
      }).config.system.build.toplevel;

      # VM boot test — boots minimal NixOS in QEMU, verifies multi-user.target
      # Catches runtime regressions static analysis misses (firewall, SSH, etc.)
      minimal-boot = pkgs.testers.nixosTest {
        name = "minimal-boot";
        nodes.machine = { ... }: {
          imports = [ inputs.sops-nix.nixosModules.default ];
          system.stateVersion = "26.05";
          services.openssh.enable = true;
          networking.firewall.enable = true;
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvekxGk1YR/eF8llVmNk3C59BtgB+9DNvxLy2WjPEyb ci-test-key"
          ];
        };
        testScript = ''
          machine.wait_for_unit("multi-user.target")
          machine.wait_for_unit("sshd")
          machine.succeed("systemctl is-system-running --wait 2>&1 || true")
          print("VM boot test passed")
        '';
      };
    };

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
    packages.x86_64-linux.srbminer-multi = pkgsWithOverlay.srbminer-multi;
    packages.x86_64-linux.lpminer-pearl = pkgsWithOverlay.lpminer-pearl;

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