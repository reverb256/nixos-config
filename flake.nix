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
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=6cdc7fc76e8bf7fde9fa43a849fcaaa70e230dee&rev=6cdc7fc76e8bf7fde9fa43a849fcaaa70e230dee";
    home-manager = {
      url = "git+https://github.com/nix-community/home-manager?ref=a45a7c451455a51ae740ec3bce4024b312809c29&rev=a45a7c451455a51ae740ec3bce4024b312809c29";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "git+https://github.com/0xc000022070/zen-browser-flake?ref=8cbde27feab69507f13a41a01ee45c2b632a8f43&rev=8cbde27feab69507f13a41a01ee45c2b632a8f43";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions/8d61e9afde605cd6c22dab68b83d7a71f0a6c5b2?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aagl = {
      url = "git+https://github.com/ezKEa/aagl-gtk-on-nix?ref=af94408291ad477cae8eed964981ab41f90eb184&rev=af94408291ad477cae8eed964981ab41f90eb184";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.url = "git+https://github.com/edolstra/flake-compat?rev=5edf11c44bc78a0d334f6334cdaf7d60d732daab";
      inputs.rust-overlay.url = "git+https://github.com/oxalica/rust-overlay?rev=a7887636a3959168bd1ba7ef24a8a70b168dcb56";
      inputs.rust-overlay.inputs.nixpkgs.follows = "aagl/nixpkgs";
    };

    noctalia = {
      url = "git+https://github.com/noctalia-dev/noctalia?ref=e2f529a4a39ce924c36f6633ded1ce0a88312ec2&rev=e2f529a4a39ce924c36f6633ded1ce0a88312ec2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "git+https://github.com/nix-community/NUR?ref=377589c277546126c0e26719bea6b2906f3ef134&rev=377589c277546126c0e26719bea6b2906f3ef134";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.flake-parts.url = "github:hercules-ci/flake-parts/17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e";
    };
    claude-native = {
      url = "git+https://github.com/ryoppippi/nix-claude-code?ref=d5964cc2ce7987c4c7f7e516877190d1c8cd8cf8&rev=d5964cc2ce7987c4c7f7e516877190d1c8cd8cf8";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    scopebuddy = {
      url = "git+https://github.com/OpenGamingCollective/ScopeBuddy?ref=150051976a2a1e64179edc7265175ba4e5f62f62&rev=150051976a2a1e64179edc7265175ba4e5f62f62";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcord = {
      url = "git+https://github.com/FlameFlag/nixcord?ref=5e2ee31f6e3a1020ac821e749aea046b12e17252&rev=5e2ee31f6e3a1020ac821e749aea046b12e17252";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.flake-parts.url = "github:hercules-ci/flake-parts/17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e";
      inputs.nixpkgs-nixcord.url = "github:NixOS/nixpkgs/8eeec934ae0dbeca3d7868c059568a65c08b2fc3";
    };
    # System hardening (Phase 0: Security Baseline)
    # https://github.com/cynicsketch/nix-mineral
    # Phase 3: MicroVM isolation (Qubes-like compartmentalization)
    # https://github.com/microvm-nix/microvm.nix
    microvm = {
      url = "git+https://github.com/microvm-nix/microvm.nix?ref=74d8374877d0d4e0fa81480793d4ab09b2b32ba5&rev=74d8374877d0d4e0fa81480793d4ab09b2b32ba5";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-mineral = {
      url = "git+https://github.com/cynicsketch/nix-mineral?ref=0642859ea18e2735c9e54a0ea53442f7d576d5cc&rev=0642859ea18e2735c9e54a0ea53442f7d576d5cc";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.flake-parts.url = "github:hercules-ci/flake-parts/17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e";
    };

    colmena = {
      url = "git+https://github.com/zhaofengli/colmena?ref=76ba0daa542880b730faec81f4e87efcaa63bc57&rev=76ba0daa542880b730faec81f4e87efcaa63bc57";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.flake-compat.url = "github:edolstra/flake-compat/5edf11c44bc78a0d334f6334cdaf7d60d732daab";
            inputs.flake-utils.url = "github:numtide/flake-utils/11707dc2f618dd54ca8739b309ec4fc024de578b";
            inputs.nix-github-actions.url = "github:nix-community/nix-github-actions/f4158fa080ef4503c8f4c820967d946c2af31ec9";
      inputs.stable.url = "github:NixOS/nixpkgs/a25ad5b1279642562d58e01e9082837d5c007d13";
    };

    disko = {
      url = "git+https://github.com/nix-community/disko?ref=ff8702b4de27f72b4c78573dfb89ec74e36abdf1&rev=ff8702b4de27f72b4c78573dfb89ec74e36abdf1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-generators = {
      url = "git+https://github.com/nix-community/nixos-generators?ref=8946737ff703382fda7623b9fab071d037e897d5&rev=8946737ff703382fda7623b9fab071d037e897d5";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.nixlib.url = "github:nix-community/nixpkgs.lib/228ab8523d81526e57a6ca342e1a919fb6d246a8";
    };
    impermanence = {
      url = "git+https://github.com/nix-community/impermanence?ref=7b1d382faf603b6d264f58627330f9faa5cba149&rev=7b1d382faf603b6d264f58627330f9faa5cba149";
      inputs.nixpkgs.follows = "";
      inputs.home-manager.follows = "";
    };
    preservation = {
      url = "path:/etc/nixos/lib/preservation";
    };
    niri = {
      # Pinned to commit that exports lib.niri.actions with spawn/spawn-sh/focus-window-previous
      # (replaces b5f81cf03… which lacked focus-window-previous and broke niri-config binds).
      url = "git+https://github.com/sodiboo/niri-flake?ref=9d808f1bb6e86239780039bc18abb64e5415cb23&rev=9d808f1bb6e86239780039bc18abb64e5415cb23";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.niri-unstable.url = "github:YaLTeR/niri/0777769e719b7c9b7c980d4ea66288bfbb4da5b3";
            inputs.xwayland-satellite-unstable.url = "github:Supreeeme/xwayland-satellite/a2b5c635d8c8c99b286967658d0d177044887eb8";
      inputs.xwayland-satellite-stable.url = "github:Supreeeme/xwayland-satellite/838e68b9ef35613524b0a76a569afdaab7d5ce8c";
      inputs.nixpkgs-stable.url = "github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41";
      inputs.niri-stable.url = "github:YaLTeR/niri/d85b524d7c07a47345eab434f471f2b7bfa2c9c3";
    };
    llm-agents = {
      url = "git+https://github.com/numtide/llm-agents.nix?ref=5c73869318afcf796a7a465b4b5e31b27f0819d4&rev=5c73869318afcf796a7a465b4b5e31b27f0819d4";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.bun2nix.url = "github:nix-community/bun2nix/5a39d717029e94163ac223aee8d5c9946cafed1c";
            inputs.flake-parts.url = "github:hercules-ci/flake-parts/17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e";
            inputs.systems.url = "github:nix-systems/default/da67096a3b9bf56a91d16901293e51ba5b49a27e";
            inputs.treefmt-nix.url = "github:numtide/treefmt-nix/db947814a175b7ca6ded66e21383d938df01c227";
    };
    nix-cachyos-kernel = {
      url = "git+https://github.com/xddxdd/nix-cachyos-kernel?rev=d286da7a8384cb7914a38e0d0652d3e9a8fbb66f";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.cachyos-kernel.url = "github:CachyOS/linux-cachyos/43bb73574ba4108df8b453486752e2b070c946be";
            inputs.cachyos-kernel-patches.url = "github:CachyOS/kernel-patches/ea739d734ec179864b21446856315bc49f7c52fa";
            inputs.flake-compat.url = "github:NixOS/flake-compat/5edf11c44bc78a0d334f6334cdaf7d60d732daab";
            inputs.flake-parts.url = "github:hercules-ci/flake-parts/17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e";
    };

    stylix = {
      url = "git+https://github.com/nix-community/stylix?ref=14814ef555d8148ab82eba5054e654cd9eae3a1f&rev=14814ef555d8148ab82eba5054e654cd9eae3a1f";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.base16.url = "github:SenchoPens/base16.nix/75ed5e5e3fce37df22e49125181fa37899c3ccd6";
            inputs.base16-helix.url = "github:tinted-theming/base16-helix/4d508123037e7851ad36ebf7d9c48b0e9e1eb581";
            inputs.firefox-gnome-theme.url = "github:rafaelmardojai/firefox-gnome-theme/5602ed62d638142c1ab31dccd01dfbfb28841225";
            inputs.flake-parts.url = "github:hercules-ci/flake-parts/17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e";
            inputs.nur.url = "github:nix-community/NUR/5ae4beea9d336e7b4492648d20e86a021ca61c0b";
            inputs.systems.url = "github:nix-systems/default/da67096a3b9bf56a91d16901293e51ba5b49a27e";
            inputs.tinted-kitty.url = "github:tinted-theming/tinted-kitty/de6f888497f2c6b2279361bfc790f164bfd0f3fa";
            inputs.tinted-schemes.url = "github:tinted-theming/schemes/010185535336bf94d815b900cd63bb0fc204e216";
            inputs.tinted-tmux.url = "github:tinted-theming/tinted-tmux/8c4e750f738a742bd73377ee41d3dadedebedef4";
            inputs.tinted-zed.url = "github:tinted-theming/base16-zed/5e8350bcd354e3241ab681a265fa6ef060c40be1";
    };
    easykubenix.url = "git+https://github.com/Lillecarl/easykubenix?ref=bd1e879b546873b7b6ab01d5e2a89fd86e7c0eec&rev=bd1e879b546873b7b6ab01d5e2a89fd86e7c0eec";

    nix-csi = {
      url = "git+https://github.com/Lillecarl/nix-csi?ref=e282e8a8fa099384cd4ffac0aa66dbf2c64f8902&rev=e282e8a8fa099384cd4ffac0aa66dbf2c64f8902";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.dinix.url = "github:lillecarl/dinix/383d944448f629813a691707b8b45ba78f4d2f6b";
            inputs.easykubenix.url = "github:lillecarl/easykubenix/f194739c7d03c0c9aa45282eddc1abaa5bab1c66";
            inputs.flake-compatish.url = "github:lillecarl/flake-compatish/30cb7674c79484293588da00f39e6cd5eb36865c";
            inputs.treefmt-nix.url = "github:numtide/treefmt-nix/db947814a175b7ca6ded66e21383d938df01c227";
    };
    hermes-agent = {
      url = "git+https://github.com/NousResearch/hermes-agent?ref=226e8de827a669e8ffa7035b27d70c19e44b1208&rev=226e8de827a669e8ffa7035b27d70c19e44b1208";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.flake-parts.url = "github:hercules-ci/flake-parts/17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e";
            inputs.npm-lockfile-fix.url = "github:jeslie0/npm-lockfile-fix/c6093acb0c0548e0f9b8b3d82918823721930fe8";
            inputs.pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs/430680a19bc85a3bda55f12e4cc1a1aadcf2e478";
            inputs.pyproject-nix.url = "github:pyproject-nix/pyproject.nix/7af23cfe91064865ecf2e835da28b45b3c6f49fd";
            inputs.uv2nix.url = "github:pyproject-nix/uv2nix/83995ef5e4ece3c9c704aa645bbff439e15a0ac3";
    };

    sops-nix = {
      url = "git+https://github.com/Mic92/sops-nix?ref=f1406619a3884cd5c47992a70b8b35c9c0fcb4c9&rev=f1406619a3884cd5c47992a70b8b35c9c0fcb4c9";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ═══════════════════════════════════════════════════════════════════
    # EXTRACTED PROJECTS — Migration in progress (see EXTRACTION-PLAN.md)
    # Uncomment each input after verifying the project builds independently.
    # When all verified, remove the original files from nixos-config.
    # ═══════════════════════════════════════════════════════════════════

    ai-gateway = {
      url = "git+https://github.com/reverb256/ai-inference-gateway?ref=76668583f69e7d96353f0865c71b5cdad70d2133&rev=76668583f69e7d96353f0865c71b5cdad70d2133";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    compute-market = {
      url = "git+https://github.com/reverb256/compute-market?ref=02eb54874adf8a0887a4878a99d33274af9d5404&rev=02eb54874adf8a0887a4878a99d33274af9d5404";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.flake-utils.url = "github:numtide/flake-utils/11707dc2f618dd54ca8739b309ec4fc024de578b";
    };
    mcp-registry = {
      url = "git+https://github.com/reverb256/mcp-registry?ref=d2d5daafaa9cd8f99feff39f8c18bbda014033b1&rev=d2d5daafaa9cd8f99feff39f8c18bbda014033b1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    caddy-ingress = {
      url = "git+https://github.com/reverb256/caddy-ingress?ref=a6bc19374ed68da7c769473e2b36cefc3355ac39&rev=a6bc19374ed68da7c769473e2b36cefc3355ac39";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gpu-proxy = {
      url = "git+https://github.com/reverb256/gpu-proxy?ref=d17e8fa40d5f539714f05b7387b30a0e831c1c12&rev=d17e8fa40d5f539714f05b7387b30a0e831c1c12";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # mining-infra removed - only exists on zephyr at /data/projects/infra/mining-infra
    llama-turboquant = {
      url = "git+https://github.com/reverb256/llama-cpp-turboquant?rev=1818bd47996da5e26edc1ac5b1a9b2543f36ff71";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # vllm = {
    #   url = "path:/home/j_kro/Projects/vllm";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    bun2nix = {
      url = "git+https://github.com/nix-community/bun2nix?ref=5a39d717029e94163ac223aee8d5c9946cafed1c&rev=5a39d717029e94163ac223aee8d5c9946cafed1c";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.flake-parts.url = "github:hercules-ci/flake-parts/17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e";
            inputs.systems.url = "github:nix-systems/default/da67096a3b9bf56a91d16901293e51ba5b49a27e";
            inputs.treefmt-nix.url = "github:numtide/treefmt-nix/db947814a175b7ca6ded66e21383d938df01c227";
    };

    pre-commit-hooks = {
      url = "git+https://github.com/cachix/pre-commit-hooks.nix?ref=bca82caa46d5ec0f5d422c61fb1e30bc51313cbe&rev=bca82caa46d5ec0f5d422c61fb1e30bc51313cbe";
      inputs.nixpkgs.follows = "nixpkgs";
            inputs.flake-compat.url = "github:NixOS/flake-compat/5edf11c44bc78a0d334f6334cdaf7d60d732daab";
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
    packages.x86_64-linux.buffy-mcp = pkgs.callPackage ./packages/buffy-mcp {};
    packages.x86_64-linux.nix-cache-proxy = pkgs.callPackage ./pkgs/nix-cache-proxy {};
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