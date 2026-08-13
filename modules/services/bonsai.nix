# Bonsai 27B llama-server deployments
#
# Self-hosted inference across the homelab. Ternary (2-bit, 6.7 GB) runs on
# larger NVIDIA GPUs when not mining; 1-bit (3.5 GB) runs everywhere.
#
#   Host          GPU(s)                          Ternary port  1-bit port
#   ──────────────────────────────────────────────────────────────────────
#   Zephyr        RTX 3090 (GPU 1) + 3060 Ti (0)  8005          1236
#   Nexus         RTX 3060 Ti                     —             1235
#   Forge         RTX 4060 (GPU 0,1)               —             8002,8006
#   Sentry        AMD RX 5600 XT (Vulkan)         —             8003
#   krash3        CPU-only                        —             8004
#
# NVIDIA hosts use the PrismML llama.cpp fork (CUDA):
#   cd /tmp/prism-llama-fork
#   NIXPKGS_ALLOW_UNFREE=1 nix build .#cuda --builders '' --max-jobs 2 --impure
# AMD hosts (sentry) use MAINLINE llama.cpp with the Vulkan backend
# (pkgs.llama-cpp). 1-bit Q1_0 Bonsai runs on mainline Vulkan — no PrismML
# fork Vulkan build required. Weights default to /models/bonsai but the
# sentry host overrides onebitModel to /srv/models (sentry has no /models).
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.bonsai;
  host = config.networking.hostName;

  # Wrap the PrismML fork CUDA binary into a package.
  # 2026-07-29: Fail-fast on misconfiguration — throw if enable is true but no
  # binaryStorePath is set, rather than silently falling back to upstream.
  # 2026-08-13: GC hazard documented. binaryStorePath is interpolated as a
  # string, invisible to the store DB — nix-collect-garbage deleted the binary
  # on forge while the wrapper survived (status 127 crash loop). builtins.storePath
  # was tried as a fix but is BANNED in pure eval (colmena deploys pure). Durable
  # fix is the unified llama-cpp flake package (packages.llama-cpp-unified):
  # hosts must point binaryStorePath at a proper flake output so colmena copies
  # it and GC keeps it. Until migrated, restore a GC'd binary by copying it from
  # a host that still has it (nexus/zephyr).
  # Durable default: the unified PrismML fork package (CUDA+Vulkan, Q1_0/Q2_0
  # repack, DSpark, CPU-MoE) from the overlay/flake. It is a REAL derivation,
  # so colmena copies it to targets and GC keeps it — no string-path hazard.
  # Hosts may still pin a specific fork store path via binaryStorePath (e.g.
  # the old 560rfa8pm build) but should migrate to the unified package.
  # Always a wrapper script named llama-server-bonsai so getExe resolves the
  # server binary (the raw package's mainProgram is llama-cli, which takes no
  # --host/--port). The unified package is interpolated as "${...}" so Nix
  # records a REAL dependency: colmena copies it, GC keeps it.
  prismBinary = if cfg.binaryStorePath != null then
    pkgs.writeShellScriptBin "llama-server-bonsai" ''
      export LD_LIBRARY_PATH="${cfg.binaryStorePath}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      exec ${cfg.binaryStorePath}/bin/llama-server "$@"
    ''
  else
    pkgs.writeShellScriptBin "llama-server-bonsai" ''
      export LD_LIBRARY_PATH="${pkgs.llama-cpp-unified}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      exec ${pkgs.llama-cpp-unified}/bin/llama-server "$@"
    '';

  # Optional PrismML fork Vulkan binary (NVIDIA/AMD fork build).
  prismVulkanBinary =
    if cfg.vulkanBinaryStorePath != null then
      pkgs.writeShellScriptBin "llama-server-bonsai-vulkan" ''
        export LD_LIBRARY_PATH="${cfg.vulkanBinaryStorePath}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        exec ${cfg.vulkanBinaryStorePath}/bin/llama-server "$@"
      ''
    else null;

  # Mainline llama.cpp (nixpkgs) with the Vulkan backend — for AMD/Radeon
  # hosts running 1-bit Q1_0 Bonsai. No fork build required.
  # CUDA support is DISABLED so the binary does not hard-link libcuda.so.1
  # (which is absent on AMD-only hosts and crashes the loader before Vulkan
  # can initialise). Vulkan backend stays enabled by default in nixpkgs.
  # VK_ICD_FILENAMES is forced to the mesa RADV ICD so llama.cpp's Vulkan
  # loader finds the GPU even when the system icd.d lacks the radeon symlink
  # (sentry's headless setup). LD_LIBRARY_PATH wires the llama.cpp libs.
  mainlineVulkanBinary =
    if cfg.vulkanMainlinePackage != null then
      pkgs.writeShellScriptBin "llama-server-bonsai-mainline-vulkan" ''
        export VK_ICD_FILENAMES="${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json"
        export LD_LIBRARY_PATH="${cfg.vulkanMainlinePackage}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        exec ${cfg.vulkanMainlinePackage}/bin/llama-server "$@"
      ''
    else null;

  # Fork (PrismML) Vulkan binary — the unified fork's Vulkan-only variant for
  # AMD-only hosts (sentry). Same fork source as llama-cpp-unified (Q1_0/Q2_0
  # repack, CPU-MoE, DSpark) minus the CUDA backend, which hard-links
  # libcuda.so.1 (DT_NEEDED) and cannot load on AMD hosts. RADV ICD forced for
  # the same reason as mainlineVulkanBinary.
  forkVulkanBinary =
    pkgs.writeShellScriptBin "llama-server-bonsai-fork-vulkan" ''
      export VK_ICD_FILENAMES="${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json"
      export LD_LIBRARY_PATH="${pkgs.llama-cpp-unified-vulkan}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      exec ${pkgs.llama-cpp-unified-vulkan}/bin/llama-server "$@"
    '';

  # turboQuant binary wrapper — wraps the retroheim turbo build.
  turboPackage = if cfg.turboBinaryStorePath != null then
    pkgs.writeShellScriptBin "llama-server-turbo-asym" ''
      exec ${cfg.turboBinaryStorePath}/llama-server-turbo "$@"
    ''
  else null;

  # Override for asymmetric KV services
  effectivePackage = if cfg.turboBinaryStorePath != null then turboPackage else cfg.package;

  # Shorthand: 1-bit Bonsai service (3.5 GB). Uses explicit context & q4_0 KV.
  # `model` and `memoryMax` are overridable per-host (sentry uses /srv/models
  # and a smaller ctx/ram cap than the 8-24 GB NVIDIA hosts). Also opens the
  # service port in the host firewall (cluster convention: mkOptionDefault).
  mk1bitService = { name, desc, port, gpu ? null, extraEnv ? {}, binary ? prismBinary, model ? cfg.onebitModel, contextSize ? "131072", cacheTypeK ? "q4_0", cacheTypeV ? "q4_0", memoryMax ? "6G", specType ? null, specDraftNMax ? null, draftModel ? null }: {
    systemd.services."bonsai-1bit-${name}" = {
      description = desc;
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = "bonsai";
        RuntimeDirectory = "bonsai-1bit-${name}";
        ExecStart = "${getExe binary} -m ${model} --host 0.0.0.0 --port ${toString port} -ngl 99 -fa on -c ${contextSize} --cache-type-k ${cacheTypeK} --cache-type-v ${cacheTypeV} --fit off --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 --jinja --parallel 1 --alias bonsai-27b-1bit-${name}"
          + optionalString (specType != null) " --spec-type ${specType}"
          + optionalString (specDraftNMax != null) " --spec-draft-n-max ${toString specDraftNMax}"
          + optionalString (draftModel != null) " -md ${draftModel}";
        Restart = "on-failure";
        RestartSec = "10";
        StandardOutput = "journal";
        StandardError = "journal";
        MemoryMax = memoryMax;
        LimitNOFILE = 65536;
        OOMScoreAdjust = 500;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = ["/run/bonsai-1bit-${name}"];
        ReadOnlyPaths = [ model ] ++ optionals (draftModel != null) [ draftModel ];
      };
      environment = optionalAttrs (gpu != null) { CUDA_VISIBLE_DEVICES = gpu; }
        // {
          # UMA OFF on every host: =1 would spill GPU memory into system RAM
          # and earlyoom-kill llama-server (observed on zephyr 2026-08-12 at
          # 51 MiB free). Explicit per-process control; never inherit session.
          GGML_CUDA_ENABLE_UNIFIED_MEMORY = "0";
        }
        // extraEnv;
    };
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ port ];
  };

  # Shorthand: Ternary Bonsai service (6.7 GB).
  mkTernaryService = { name, desc, port, gpu, memoryMax ? "20G", extraFlags ? "", extraEnv ? {} }: {
    systemd.services."bonsai-ternary-${name}" = {
      description = desc;
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = "bonsai";
        RuntimeDirectory = "bonsai-ternary-${name}";
        ExecStart = "${getExe prismBinary} -m ${cfg.ternaryModel}"
          + (if cfg.dsparkModel != null then " --spec-type draft-dspark --model-draft ${cfg.dsparkModel} --spec-draft-n-max 4" else "")
          + (if cfg.mmproj != null then " --mmproj ${cfg.mmproj}" else "")
          + " --host 0.0.0.0 --port ${toString port} -ngl 99 -fa on -c 262144 --cache-type-k q8_0 --cache-type-v q8_0 --fit off --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 --jinja --parallel 1 --alias ternary-bonsai-27b-${name}";
        Restart = "on-failure";
        RestartSec = "10";
        StandardOutput = "journal";
        StandardError = "journal";
        MemoryMax = memoryMax;
        LimitNOFILE = 65536;
        OOMScoreAdjust = 500;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = ["/run/bonsai-ternary-${name}"];
        ReadOnlyPaths = [cfg.ternaryModel] ++ optional (cfg.mmproj != null) cfg.mmproj ++ optional (cfg.dsparkModel != null) cfg.dsparkModel;
      };
      environment = {
        CUDA_VISIBLE_DEVICES = gpu;
        CUDA_CACHE_DISABLE = "1";
        # UMA OFF on every host (see mk1bitService note; same earlyoom risk).
        GGML_CUDA_ENABLE_UNIFIED_MEMORY = "0";
      } // extraEnv;
    };
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ port ];
  };

  # ── All services, each gated by hostname ──

  # Ternary on zephyr 3090 (CUDA0 = 24 GB) — full capabilities including vision + DSpark
  # NOTE: llama.cpp enumerates CUDA0 = RTX 3090, CUDA1 = RTX 3060 Ti — the
  # REVERSE of nvidia-smi (GPU0 = 3060 Ti, GPU1 = 3090). GPU pinning uses
  # CUDA_VISIBLE_DEVICES, so ternary (24 GB card) = "0", 1-bit (8 GB) = "1".
  # DISABLED on zephyr: home-manager owns zephyr bonsai (user units). The
  # system unit uses User=bonsai, which does not exist on zephyr -> status=217
  # crash-loop that fails the colmena post-activation health check on EVERY
  # zephyr deploy (2026-08-13). Re-enable only if zephyr bonsai moves back to
  # systemd-system management AND the bonsai user is created.
  ternaryZephyr = mkIf (host == "zephyr" && false) (mkTernaryService {
    name = "zephyr"; desc = "Bonsai 27B Ternary — Zephyr RTX 3090 (port 8005) q8_0 KV + DSpark";
    port = 8005; gpu = "0"; memoryMax = "20G";
    extraEnv = { GGML_CUDA_GRAPH_OPT = "1"; LLAMA_ATTN_ROT_DISABLE = "1"; CUDA_SCALE_LAUNCH_QUEUES = "4"; LD_LIBRARY_PATH = "/usr/local/lib/bonsai-turbo:/run/opengl-driver/lib"; };
  });

  # 1-bit on zephyr 3060 Ti (CUDA1 = 8 GB) — explicit 128K + q4_0 KV
  # DISABLED on zephyr: HM owns zephyr bonsai (see ternaryZephyr note).
  bit1Zephyr = mkIf (host == "zephyr" && false) (mk1bitService {
    name = "zephyr"; desc = "Bonsai 27B 1-bit — Zephyr RTX 3060 Ti (port 1236) q4_0 KV 128K";
    port = 1236; gpu = "1";
  });

  # 1-bit on nexus 3060 Ti (8 GB)
  bit1Nexus = mkIf (host == "nexus" && true) (mk1bitService {
    name = "nexus"; desc = "Bonsai 27B 1-bit — Nexus RTX 3060 Ti (port 1235) q4_0 KV 128K";
    port = 1235;
  });

  # NOTE: ternary on nexus was REMOVED (2026-08-12). The 3060 Ti is an 8 GB
  # card shared with ComfyUI + peakminer + gamescope (~3 GB busy); ternary
  # (6.7 GB) + DSpark drafter never fit -> cudaMalloc OOM -> 119 restarts.
  # Nothing consumed port 1238. If GPU-idle scheduling is ever wanted, add a
  # proper gate (stop 1-bit + require <1 GB GPU busy) — do NOT re-enable
  # unconditionally.

  # 1-bit on forge 4060 GPU 0 (8 GB)
  bit1Forge0 = mkIf (host == "forge" && true) (mk1bitService {
    name = "forge-0"; desc = "Bonsai 27B 1-bit — Forge RTX 4060 GPU 0 (port 8002) q4_0 KV 128K";
    port = 8002; gpu = "0";
  });

  # 1-bit on forge 4060 GPU 1 (8 GB)
  bit1Forge1 = mkIf (host == "forge" && cfg.enableForge1) (mk1bitService {
    name = "forge-1"; desc = "Bonsai 27B 1-bit — Forge RTX 4060 GPU 1 (port 8006) q4_0 KV 128K";
    port = 8006; gpu = "1";
  });

  # NOTE: ternary on forge was REMOVED (2026-08-12) — same root cause as nexus:
  # both 4060s mine 24/7 at 100% util on 8 GB cards; ternary (6.7 GB) +
  # drafter never fit -> 379 restarts. Ternary is zephyr-only (24 GB 3090).
  # Do NOT re-enable without a real idle gate.

  # 1-bit on sentry AMD via MAINLINE llama.cpp Vulkan (no fork build).
  # 5600 XT has 6 GB VRAM — Bonsai is hybrid-attention (only 16/64 layers
  # cache), so KV is small. Testing how far -c can go on 6 GB (q4_0 KV).
  # VK_ICD_FILENAMES forces RADV discovery. CUDA disabled (no libcuda on AMD).
  # NO DSpark drafter here: mainline llama.cpp cannot load the 'dspark' draft
  # architecture (unknown model architecture: 'dspark' -> exit 1 -> crash loop),
  # and the drafter never fit 6 GB VRAM anyway (3060 Ti history: OOM -> 119/379
  # restarts). Plain 1-bit Vulkan is the stable config.
  bit1Sentry = mkIf (host == "sentry") (mk1bitService {
    name = "sentry"; desc = "Bonsai 27B 1-bit — Sentry AMD RX 5600 XT via Vulkan (port 8003)";
    port = 8003; binary = forkVulkanBinary;
    extraEnv = { GGML_VULKAN_DEVICE = "0"; VK_ICD_FILENAMES = "${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json"; };
    contextSize = "8192"; cacheTypeK = "q4_0"; cacheTypeV = "q4_0"; memoryMax = "8G";
  });

  # 1-bit on krash3 CPU-only (no GPU available)
  bit1Krash3 = mkIf (host == "krash3") (mk1bitService {
    name = "krash3"; desc = "Bonsai 27B 1-bit — krash3 CPU-only (port 8004)";
    port = 8004; extraEnv = {};
    contextSize = "131072"; cacheTypeK = "q4_0"; cacheTypeV = "q4_0";
  });

in {
  options.services.bonsai = {
    enable = mkEnableOption "Bonsai 27B llama-server inference";

    binaryStorePath = mkOption {
      # types.path: an in-store string coerces to a path VALUE, so the wrapper
      # interpolates with string context -> Nix records a real dependency and
      # GC keeps the fork alive. Pure-eval-safe (builtins.storePath is not).
      type = types.nullOr types.path;
      default = null;
      description = ''
        Store path of the built PrismML llama.cpp fork (nix build .#cuda output). NVIDIA hosts.
        The path is wrapped with builtins.storePath so Nix records a real dependency: the
        fork cannot be garbage-collected while this config references it, and eval fails
        loudly if the path is missing on the builder (nexus). Copy the fork closure to the
        builder first: nix-copy-closure --to nexus <store-path>.
      '';
      example = "/nix/store/00000000000000000000000000000000-llama-cpp-cuda";
    };

    vulkanBinaryStorePath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Store path of the PrismML fork built with Vulkan (AMD/Radeon hosts). Optional.";
      example = "/nix/store/xxx-llama-cpp-vulkan-0.0.0";
    };

    vulkanMainlinePackage = mkOption {
      type = types.nullOr types.package;
      default = pkgs.llama-cpp.override { cudaSupport = false; vulkanSupport = true; };
      description = "Mainline llama.cpp package with Vulkan backend and CUDA disabled (AMD/Radeon 1-bit Q1_0). No fork needed.";
      example = "pkgs.llama-cpp.override { cudaSupport = false; vulkanSupport = true; }";
    };

    package = mkOption {
      type = types.package;
      default = prismBinary;
      description = "PrismML llama.cpp package. Defaults to binaryStorePath wrapper.";
    };

    ternaryModel = mkOption {
      type = types.str;
      default = "/models/bonsai/ternary-27b/Ternary-Bonsai-27B-Q2_0.gguf";
    };

    onebitModel = mkOption {
      type = types.str;
      default = "/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
    };

    dsparkModel = mkOption {
      type = types.nullOr types.str;
      default = "/models/bonsai/dspark/Ternary-Bonsai-27B-dspark-Q4_1.gguf";
    };

    mmproj = mkOption {
      type = types.nullOr types.str;
      default = "/models/bonsai/ternary-27b/Ternary-Bonsai-27B-mmproj-Q8_0.gguf";
    };

    turboBinaryStorePath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to turboQuant llama-server-turbo binary (retroheim fork)";
      example = "/home/j_kro/.local/share/bonsai/bin/llama-server-turbo";
    };

    enableForge1 = mkOption {
      type = types.bool;
      default = true;
      description = "Run the second forge bonsai service (GPU 1). Disable when the GPU 1 miner holds most VRAM — the 3.5GB 1-bit model SIGSEGVs on allocation (libnvidia-eglcore) with <1GB free.";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      users.users.bonsai = {
        isSystemUser = true;
        group = "bonsai";
        description = "Bonsai 27B inference service";
      };
      users.groups.bonsai = {};
    })
    ternaryZephyr
    bit1Zephyr
    bit1Nexus
    bit1Forge0
    bit1Forge1
    bit1Sentry
    bit1Krash3
  ];
}
