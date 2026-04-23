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

    easykubenix.url = "github:Lillecarl/easykubenix";

    # Phase 3: nix-csi -- mount /nix into pods via CSI ephemeral volumes
    # See kubernetes/modules/nix-csi-README.md for details
    nix-csi = {
      url = "github:Lillecarl/nix-csi";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
      url = "github:reverb256/ai-inference-gateway";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    knowledge-fabric = {
      url = "github:reverb256/knowledge-fabric";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llama-turboquant = {
      url = "github:reverb256/llama-cpp-turboquant";
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
    astral-key = {
      url = "github:reverb256/astral-key";
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
      nix-mineral,
      colmena,
      pre-commit-hooks,
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
        overlays = [ ((import ./overlay.nix) { inherit inputs; }) ];
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


      checks.x86_64-linux = {};

      nixosConfigurations = (builtins.mapAttrs (
        _name: value: mkNixosSystem { inherit (value) hostName; }
      ) hosts) // {
        # Phase 3: MicroVM configurations (not regular hosts, not managed by Colmena)
        ci-test = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./hosts/ci-test/configuration.nix ];
          specialArgs = { inherit inputs; };
        };
      };

      colmena = import ./colmena.nix {
        inherit inputs self;
        inherit hosts;
      };

      colmenaHive = colmena.lib.makeHive self.outputs.colmena;

      packages.x86_64-linux.claude = claude-native.packages.x86_64-linux.claude;
      packages.x86_64-linux.llama-cpp = pkgsWithOverlay.llama-cpp;
      packages.x86_64-linux.caddy-with-modules = inputs.caddy-ingress.packages.x86_64-linux.caddy-with-modules;
      packages.x86_64-linux.caddy-ingress-image = inputs.caddy-ingress.packages.x86_64-linux.caddy-ingress-image;

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

      # packages.x86_64-linux.lolminer-image = inputs.compute-market.packages.x86_64-linux.lolminer-image; # migrated
      # packages.x86_64-linux.lolminer-amd-image = inputs.compute-market.packages.x86_64-linux.lolminer-amd-image; # migrated
      packages.x86_64-linux.xmrig-nixos-image = inputs.compute-market.packages.x86_64-linux.xmrig-nixos-image; # migrated
      packages.x86_64-linux.xmrig-alpine-image = inputs.compute-market.packages.x86_64-linux.xmrig-alpine-image; # migrated
      packages.x86_64-linux.xmrig-proxy-alpine-image = inputs.compute-market.packages.x86_64-linux.xmrig-proxy-alpine-image; # migrated
      packages.x86_64-linux.claude-code-image = pkgsWithOverlay.claude-code-image; # extracted to packages/claude-code-image.nix
      packages.x86_64-linux.ai-inference-gateway-image = inputs.ai-gateway.packages.x86_64-linux.container; # migrated from local pkgs/
      packages.x86_64-linux.opencode-image = pkgsWithOverlay.opencode-image; # extracted to packages/opencode-image.nix
      overlays.default = (import ./overlay.nix) { inherit inputs; };
      kubernetes = import ./kubernetes { inherit pkgs pkgsWithOverlay inputs; };


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
