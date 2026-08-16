{
  description = "NixOS configuration with Garage and Syncthing storage";

  inputs = {
    # Pinned to the lock rev for multi-host build reproducibility. When colmena
    # builds a host ON-TARGET (e.g. forge on nexus), the target re-evaluates the
    # hive; with only "?ref=nixos-unstable" in the URL it falls back to the
    # nixos-unstable channel HEAD (divergent nixpkgs -> curl-cffi hash mismatch
    # between builder and dispatcher). Pinning the rev makes every builder
    # resolve the SAME nixpkgs regardless of which host evaluates.
    # To bump nixpkgs: edit this rev AND run `nix flake update`.
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?rev=0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5";
    # Homelab Lix fork: build nix.package from the patched source instead of
    # nixpkgs' lix_2_95. The source of truth is the `homelab/2.96` branch of
    # reverb256/lix — a fork of lix-project/lix carrying the 4 homelab
    # patches IN-TREE (zngur codegen ordering, lix-rs test gating, Boehm GC
    # heap cap, attr-set linear scan). Pinned to a specific commit, never the
    # branch head: evaluation happens on nexus from origin/main, and pinning
    # keeps every builder resolving the SAME tree (see the nixpkgs input
    # comment for the same reasoning). Bump by pushing the fork branch,
    # re-running CI (it builds .#nix with the test suite), then pinning the
    # new tip here. flake=false: we only consume the source tree; nixpkgs'
    # common-lix.nix build glue stays in charge.
    lix = {
      url = "git+https://github.com/reverb256/lix?ref=homelab%2F2.96&rev=880fec9d10c8874d787eb2588e65fbc218950009";
      flake = false;
    };
    # zen-browser: pin rev + let it use its OWN pinned nixpkgs (1559d3da…) for
    # the zen package instead of our floating nixos-unstable. zen-twilight.desktop
    # embeds the zen version; following our nixpkgs made it drift every time
    # nixos-unstable's zen moved, and zephyr-eval vs forge-build-cache diverged
    # on that version -> "hash mismatch importing zen-twilight.desktop". Freezing
    # zen-browser's nixpkgs (its own lock) makes the .desktop deterministic.
    zen-browser = {
      url = "git+https://github.com/0xc000022070/zen-browser-flake?rev=e1a0481218312579ad67eda819ad964176fbe28b";
    };
    # lsfg-vk - Lossless Scaling Frame Generation on Linux
    lsfg-vk-nix = {
      url = "git+https://github.com/Daaboulex/lsfg-vk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    firefox-addons = {
      url = "git+https://gitlab.com/rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # NOTE: freebuff-flake input REMOVED (2026-08-13, duplication reconcile).
    # The Freebuff binary is packaged locally at packages/freebuff-desktop.nix
    # (wrapType2, verified hash) and installed via environment.systemPackages;
    # the flake was declared but never consumed, and its pinned hash was stale.
    # home-manager - Lix github:-fetcher cannot resolve implicit registry refs.
    # Declared explicitly with git+https:// transport (same sweep as other inputs).
    home-manager = {
      url = "git+https://github.com/nix-community/home-manager";
    };
    # home-manager-config - standalone Home Manager configuration (Layer 2)
    # Migrated from modules/home-manager/ to separate flake per 3-layer model.
    home-manager-config = {
      url = "git+https://github.com/reverb256/home-manager-config";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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
      url = "git+https://github.com/dividebysandwich/niri?ref=hdr-smithay-master";
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
      url = "git+https://github.com/reverb256/mcp-registry";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # caddy-ingress - Caddy ingress module + caddy-with-modules package
    caddy-ingress = {
      url = "git+https://github.com/reverb256/caddy-ingress";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # gpu-proxy - GPU proxy module
    gpu-proxy = {
      url = "git+https://github.com/reverb256/gpu-proxy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # flake-parts — transitive dep for 6 inputs, use git+https to bypass GitHub API 401
    flake-parts = {
      url = "git+https://github.com/hercules-ci/flake-parts";
    };
    # noctalia REMOVED — upstreamed into nixpkgs-unstable as programs.noctalia
    # + pkgs.noctalia. The flake input is no longer needed.
    # stylix - theming module
    stylix = {
      url = "git+https://github.com/nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixpkgs-secretspec REMOVED — nixpkgs is now nixos-unstable, so
    # secretspec 0.17.0 with native sops provider is available directly.

    # gitlawb - local option-4 flake: packages + overlay + NixOS module
    # Fetched as a subdirectory of this repo (dir=). A plain path:./pkgs/gitlawb
    # input breaks when the flake is fetched remotely (deploy-nexus fetches
    # origin/main -> 'cannot fetch input ... relative path' blocked every
    # host eval 2026-08-14). dir= resolves from GitHub in both contexts.
    gitlawb = {
      url = "git+https://github.com/reverb256/nixos-config?dir=pkgs/gitlawb";
    };

    # preservation - ephemeral-root persistence (sentry/nexus /persistent symlinks).
    # Required by hosts/sentry/preservation.nix (inputs.preservation.nixosModules.preservation).
    # Was missing from inputs -> sentry persistence module failed to eval and was
    # never imported; host keys + age keys rotated on every rebuild.
    preservation = {
      url = "git+https://github.com/nix-community/preservation";
    };
    # llama-cpp-turboquant - TheTom/llama-cpp-turboquant fork: TurboQuant KV
    # (turbo2/3/4 + TQ3_1S/TQ4_1S) + ALL fleet archs in one tree — Bonsai
    # (granite-hybrid Q1_0/Q2_0), Nemotron Lightning (nemotron_h_moe), Muse
    # Glimmer (muse_glimmer), DSpark draft, n-cpu-moe, web UI (LLAMA_BUILD_WEBUI).
    # This SUPERSEDES retroheim/prism-ml-llama.cpp (176bc4f) which lacked
    # nemotron_h_moe + muse_glimmer and stalled on the Nemotron 30B tensor set.
    # Pinned: 2026-08-13 "Merge pull request #283 from jasstrong/tq3-fused-hip".
    llama-cpp-turboquant = {
      # OUR fork (reverb256): mainline qwen35 + ssm_scan rollback + TurboQuant KV.
      # main-qwen35 @ 478caed42 (merge of TheTom turbo onto mainline 1692f9e5).
      url = "git+https://github.com/reverb256/llama-cpp-turboquant?ref=main-qwen35&rev=478caed42747ccc8a6fbd0d946252bc3e29a526b";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    home-manager,
    home-manager-config,
    aagl,
    nur,
    claude-native,
    colmena,
    nixpkgs-xr,
    ...
  }:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} (
      {config, ...}: {
        systems = ["x86_64-linux"];

        imports = [
          # B namespace: class-checked flake.modules.nixos.* (self-registering
          # feature modules; a Home Manager module loaded into a NixOS config
          # becomes a simple type error).
          inputs.flake-parts.flakeModules.modules
          # nixpkgs flakeModule: provides perSystem.pkgs + perSystem.nixpkgs.config
          # (allowUnfree for checks/packages, mirroring the classic flake's
          # top-level `import nixpkgs { config.allowUnfree = true; }`).
          inputs.flake-parts.flakeModules.nixpkgs
          # Dendritic host registry: ALL FOUR hosts live here
          # (modules/hosts/<n>). Migration complete 2026-08-13 (issue #397).
          ./modules/hosts/default.nix
        ];

        # ── DENDRITIC HOST WIRING (dissolved) ────────────────────────────────
        # All four cluster hosts are dendritic (modules/hosts/<n>/default.nix,
        # issue #397, complete 2026-08-13). This `flake` block no longer carries
        # the legacy mkNixosSystem shim, the classic-hosts carve-out, or the
        # pre-dendritic compatibility oracle — all dissolved after phase-1b
        # parity (hostName + stateVersion) passed for every host. It keeps only
        # the typed inventory + commonModules (consumed by colmena.nix) and the
        # standalone portable rescue config.
        flake = let
          # COMMON MODULES - Shared across all hosts (single source of truth)
          # Host identity/deployment/capability facts live in the typed inventory;
          # NixOS and Colmena consume the same value instead of duplicating it.
          hostInventory = import ./contracts/host-inventory.nix;
          hosts = hostInventory.hosts;
          commonModules = import ./common-modules-list.nix {
            inherit inputs self;
          };

          # HOST DEFINITIONS - derived from the canonical typed inventory.
          # hostName: matches ./hosts/<n>/ and networking.hostName
          # targetHost: colmena targetHost (IP/hostname for remote, null = local)
          # buildOnTarget: colmena buildOnTarget (true=build-on-remote, false=build elsewhere)
          # tags: colmena tag set for selective deploys
          # extraModules: per-host NixOS modules appended after commonModules
          # (use this to selectively load desktop-only modules for
          # zephyr/forge while keeping nexus/sentry free of niri/etc)
          # Adding a 5th host = 1 attr in contracts/host-inventory.nix +
          # ./hosts/<n>/configuration.nix + a host file under modules/hosts/<n>/.
          #   NOTE: also update ./machines (its keys are colmena machine entries).

          # Portable USB stick — standalone rescue/pinch config (wayfinder #421/#425).
          # Shared by nixosConfigurations.portable and packages.portable-image.
          portableConfig = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {inherit inputs;};
            modules = [./modules/profiles/portable-usb.nix];
          };
        in {
          # OUTPUT 1: nixosConfigurations — cluster hosts come from the
          # dendritic registry (modules/hosts/<n>/default.nix, imported via
          # ./modules/hosts/default.nix); only the standalone portable rescue
          # config is declared here.

          nixosConfigurations = {
            # Deliberately OUTSIDE the cluster hive (no commonModules: no
            # sops-nix / peakminer / mcp-registry / caddy). Built only as a
            # systemd-repart disk image (see modules/profiles/portable-usb.nix).
            # Wayfinder map #421; contract #425.
            portable = portableConfig;
          };

          # OUTPUT 2: colmena (raw hive configuration)
          # The typed inventory is the whole-cluster source of truth.
          # `colmena.nix` derives both `meta.nodeNixpkgs` AND each host's
          # colmena `meta` from it, and composes host modules via the shared
          # lib/dendritic-host.nix evaluator (same module list + specialArgs
          # contract as nixosConfigurations). No duplicate host declarations.

          colmena = import ./colmena.nix {
            inherit inputs self hosts commonModules;
          };

          # OUTPUT 3: colmenaHive (for multi-host deployment)
          # Wraps the raw hive configuration with makeHive for proper schema
          # validation. Reads config.flake.colmena (not self.outputs.colmena)
          # to avoid the self-referential cycle flake-parts introduces.

          colmenaHive = colmena.lib.makeHive config.flake.colmena;

          overlays.default = import ./overlays/default.nix {inherit inputs;};

          # OUTPUT 4: homeConfigurations — consumed from standalone home-manager-config flake
          # Layer 2 of the 3-layer model (NixOS / Home Manager / nix profile).
          # The standalone flake manages its own inputs (nixcord, zen-browser,
          # stylix, niri) and patches (noctalia SDR brightness). It exposes homeConfigurations
          # keyed by hostName (zephyr/nexus/forge/sentry) for colmena deployment.
          homeConfigurations = inputs.home-manager-config.homeConfigurations;
        };

        # ── OUTPUT 5: checks — source-level test suite (runs via `nix flake check`)
        # Each tests/*.nix (except lib.nix) is imported with the flake's pkgs
        # and must evaluate `passed == true` / `all_pass == true`. A failing
        # test throws, which fails `nix flake check` in CI — the P0 eval gate.
        # (Fixes: CI tests job never asserted results; flake exported no checks.)

        perSystem = {
          system,
          pkgs,
          ...
        }: {
          # Custom pkgs: this flake-parts rev's nixpkgs flakeModule sets
          # `_module.args.pkgs` via `lib.mkOptionDefault` (unconfigured
          # legacyPackages); override it with the classic-flake-equivalent
          # configured instance so checks/packages see allowUnfree exactly as
          # the pre-cutover `pkgs = import nixpkgs { config.allowUnfree = true; }`.
          _module.args.pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [(import ./overlays/default.nix {inherit inputs;})];
          };

          checks = let
            mkCheck = name: file: let
              result = import file {inherit pkgs;};
              passed = result.passed or result.all_pass or false;
              failures = result.failures or [];
            in
              if passed
              then pkgs.runCommand "check-${name}" {} "echo '${name}: PASS'; touch $out"
              else throw "test ${name} FAILED: ${builtins.toJSON failures}";
          in {
            firewall-lint = mkCheck "firewall-lint" ./tests/firewall-lint.nix;
            flake-input-consistency = mkCheck "flake-input-consistency" ./tests/flake-input-consistency.nix;
            host-configuration = mkCheck "host-configuration" ./tests/host-configuration.nix;
            import-integrity = mkCheck "import-integrity" ./tests/import-integrity.nix;
            infrastructure-consistency = mkCheck "infrastructure-consistency" ./tests/infrastructure-consistency.nix;
            integration-smoke = mkCheck "integration-smoke" ./tests/integration-smoke.nix;
            k3s-cluster = mkCheck "k3s-cluster" ./tests/k3s-cluster.nix;
            k3s-topology-evidence = mkCheck "k3s-topology-evidence" ./tests/k3s-topology-evidence.nix;
            k8s-manifest-validation = mkCheck "k8s-manifest-validation" ./tests/k8s-manifest-validation.nix;
            mcp-hermes-yaml = mkCheck "mcp-hermes-yaml" ./tests/mcp-hermes-yaml.nix;
            module-template-compliance = mkCheck "module-template-compliance" ./tests/module-template-compliance.nix;
            dualsense = mkCheck "dualsense" ./tests/dualsense.nix;
            network-constants = mkCheck "network-constants" ./tests/network-constants.nix;
            nixos-eval = mkCheck "nixos-eval" ./tests/nixos-eval.nix;
            nixos-sync = mkCheck "nixos-sync" ./tests/nixos-sync.nix;
            portable-model-purity = mkCheck "portable-model-purity" ./tests/portable-model-purity.nix;

            options-consistency = mkCheck "options-consistency" ./tests/options-consistency.nix;
            secrets-integrity = mkCheck "secrets-integrity" ./tests/secrets-integrity.nix;
            zephyr-dispatcher-policy = mkCheck "zephyr-dispatcher-policy" ./tests/zephyr-dispatcher-policy.nix;
            layer-interface-contract = mkCheck "layer-interface-contract" ./tests/layer-interface-contract.nix;
            inventory-compliance = mkCheck "inventory-compliance" ./tests/inventory-compliance.nix;
            dendritic-parity = mkCheck "dendritic-parity" ./tests/dendritic-parity.nix;
          };

          # EXISTING OUTPUTS (maintain compatibility)

          packages.claude = claude-native.packages.x86_64-linux.claude;
          packages.llama-cpp = pkgs.llama-cpp;
          # One llama.cpp binary with BOTH CUDA and Vulkan backends + TurboQuant
          # KV + PrismML Bonsai support, covering the whole fleet: NVIDIA
          # 3090/3060 Ti (CUDA) + Navi 10 Radeons on forge/sentry (Vulkan).
          # Source: retroheim/prism-ml-llama.cpp (PrismML + TheTom TurboQuant),
          # pinned input. Turbo KV types (turbo2/3/4) compile in with the
          # backends — required for 256k context on 8 GB cards without RAM spill.
          # Provided by overlays/llama.nix so host configs resolve the same drv.
          packages.llama-cpp-unified = pkgs.llama-cpp-unified;
          # AMD-only variant (useCuda=false): the CUDA+Vulkan build hard-links
          # libcuda.so.1 and cannot load on AMD-only hosts (sentry). Same
          # retroheim turboquant fork, Vulkan backend only.
          packages.llama-cpp-unified-vulkan = pkgs.llama-cpp-unified-vulkan;
          packages.secretspec = pkgs.secretspec;
          # llama-swap — model swapping proxy (mostlygeek v240, same version
          # zephyr's home-manager runs). System-layer package for the cluster
          # llama-swap services on nexus/forge/sentry.
          packages.llama-swap = pkgs.llama-swap;
          # chatterbox-tts — neural TTS wrapper script (POSTs to the chatterbox
          # container on forge :8004). Exposed as a flake package so Layer 2
          # (home-manager-config) can install it via home.packages with a real
          # store dependency (GC-safe) — previously a hand-placed ~/.local/bin
          # symlink lost its closure to nix-collect-garbage (exit 127).
          packages.chatterbox-tts = pkgs.chatterbox-tts;
          # CONTAINER IMAGES (for Kubernetes deployment)

          # Claude Code container image for Kubernetes deployment
          # Container images extracted to pkgs/ on 2026-07-29 (audit change 3).
          # /etc/nixos/pkgs/claude-code-image/default.nix — pkgs.callPackage'd.
          # /etc/nixos/pkgs/opencode-image/default.nix — pkgs.callPackage'd.
          packages.claude-code-image =
            pkgs.callPackage ./pkgs/claude-code-image {};
          packages.opencode-image =
            pkgs.callPackage ./pkgs/opencode-image {};
          packages.ai-inference-gateway-image =
            pkgs.callPackage ./pkgs/ai-inference-gateway-image
            {};
          # NVIDIA Switchyard LLM routing proxy (standalone server binary).
          # Build on nexus: nix build .#switchyard-server
          packages.switchyard-server =
            pkgs.callPackage ./pkgs/switchyard-server {};
          # Portable USB stick disk image (systemd-repart, persistent).
          # Build: nix build .#portable-image
          # Flash: sudo dd if=result/portable-image of=/dev/disk/by-id/usb-... bs=4M status=progress oflag=sync
          packages.portable-image =
            (nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              specialArgs = {inherit inputs;};
              modules = [./modules/profiles/portable-usb.nix];
            }).config.system.build.image;
          # Requires impure paths - build manually: nix build .#kb-mcp-image --impure
          # packages.kb-mcp-image = pkgs.callPackage ./pkgs/kb-mcp-image { };
          # Boots a VM with the homelab Lix as nix-daemon and exercises it.
          # Build/run: nix build .#lix-vm-test
          packages.lix-vm-test =
            import ./tests/lix-vm.nix {inherit pkgs inputs;};

          apps.colmena = {
            type = "app";
            program = "${colmena.packages.x86_64-linux.colmena}/bin/colmena";
            meta.description = "Colmena multi-host NixOS deployment";
          };
          # ── FORMATTING GATE ───────────────────────────────────────
          # `nix fmt` -> alejandra (format) across the tree.
          formatter = pkgs.alejandra;
        };
      }
    );
}
