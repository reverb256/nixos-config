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
  prismBinary = if cfg.binaryStorePath != null then
    pkgs.writeShellScriptBin "llama-server-bonsai" ''
      export LD_LIBRARY_PATH="${cfg.binaryStorePath}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      exec ${cfg.binaryStorePath}/bin/llama-server "$@"
    ''
  else
    throw ''
      services.bonsai.binaryStorePath is null but services.bonsai.enable is true.

      Build the PrismML fork per the instructions in the header of this file,
      then point services.bonsai.binaryStorePath at the resulting store path.
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
  mk1bitService = { name, desc, port, gpu ? null, extraEnv ? {}, binary ? prismBinary, model ? cfg.onebitModel, contextSize ? "131072", cacheTypeK ? "q4_0", cacheTypeV ? "q4_0", memoryMax ? "6G" }: {
    systemd.services."bonsai-1bit-${name}" = {
      description = desc;
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = "bonsai";
        RuntimeDirectory = "bonsai-1bit-${name}";
        ExecStart = "${getExe binary} -m ${model} --host 0.0.0.0 --port ${toString port} -ngl 99 -fa on -c ${contextSize} --cache-type-k ${cacheTypeK} --cache-type-v ${cacheTypeV} --fit off --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 --jinja --parallel 1 --alias bonsai-27b-1bit-${name}";
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
        ReadOnlyPaths = [model];
      };
      environment = optionalAttrs (gpu != null) { CUDA_VISIBLE_DEVICES = gpu; } // extraEnv;
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
      } // extraEnv;
    };
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ port ];
  };

  # ── All services, each gated by hostname ──

  # Ternary on zephyr 3090 (GPU 1, 24 GB) — full capabilities including vision + DSpark
  ternaryZephyr = mkIf (host == "zephyr" && cfg.binaryStorePath != null) (mkTernaryService {
    name = "zephyr"; desc = "Bonsai 27B Ternary — Zephyr RTX 3090 (port 8005) q8_0 KV + DSpark";
    port = 8005; gpu = "1"; memoryMax = "20G";
    extraEnv = { GGML_CUDA_GRAPH_OPT = "1"; LLAMA_ATTN_ROT_DISABLE = "1"; CUDA_SCALE_LAUNCH_QUEUES = "4"; LD_LIBRARY_PATH = "/usr/local/lib/bonsai-turbo:/run/opengl-driver/lib"; };
  });

  # 1-bit on zephyr 3060 Ti (GPU 0, 8 GB) — explicit 128K + q4_0 KV
  bit1Zephyr = mkIf (host == "zephyr" && cfg.binaryStorePath != null) (mk1bitService {
    name = "zephyr"; desc = "Bonsai 27B 1-bit — Zephyr RTX 3060 Ti (port 1236) q4_0 KV 128K";
    port = 1236; gpu = "0";
  });

  # 1-bit on nexus 3060 Ti (8 GB)
  bit1Nexus = mkIf (host == "nexus" && cfg.binaryStorePath != null) (mk1bitService {
    name = "nexus"; desc = "Bonsai 27B 1-bit — Nexus RTX 3060 Ti (port 1235) q4_0 KV 128K";
    port = 1235;
  });

  ternaryNexus = mkIf (host == "nexus" && cfg.binaryStorePath != null) (mkTernaryService {
    name = "nexus"; desc = "Bonsai 27B Ternary — Nexus RTX 3060 Ti (port 1238, when GPU idle) q8_0 KV";
    port = 1238; gpu = "0"; memoryMax = "8G";
  });

  # 1-bit on forge 4060 GPU 0 (8 GB)
  bit1Forge0 = mkIf (host == "forge" && cfg.binaryStorePath != null) (mk1bitService {
    name = "forge-0"; desc = "Bonsai 27B 1-bit — Forge RTX 4060 GPU 0 (port 8002) q4_0 KV 128K";
    port = 8002; gpu = "0";
  });

  # 1-bit on forge 4060 GPU 1 (8 GB)
  bit1Forge1 = mkIf (host == "forge" && cfg.binaryStorePath != null) (mk1bitService {
    name = "forge-1"; desc = "Bonsai 27B 1-bit — Forge RTX 4060 GPU 1 (port 8006) q4_0 KV 128K";
    port = 8006; gpu = "1";
  });

  # Ternary on forge 4060 — tight fit (6.7 GB on 8 GB), starts when miners idle
  ternaryForge = mkIf (host == "forge" && cfg.binaryStorePath != null) (mkTernaryService {
    name = "forge"; desc = "Bonsai 27B Ternary — Forge RTX 4060 (port 8005, when GPU idle, tight) q8_0 KV";
    port = 8005; gpu = "0"; memoryMax = "8G";
  });

  # 1-bit on sentry AMD via MAINLINE llama.cpp Vulkan (no fork build).
  # 5600 XT has 6 GB VRAM — clamp ctx to 8192 and RAM cap to 8G so the model
  # (3.6 GB) + q4_0 KV actually fit. VK_ICD_FILENAMES forces RADV discovery.
  # CUDA is disabled in the package so libcuda.so.1 is not required.
  bit1Sentry = mkIf (host == "sentry") (mk1bitService {
    name = "sentry"; desc = "Bonsai 27B 1-bit — Sentry AMD RX 5600 XT via Vulkan (port 8003)";
    port = 8003; binary = mainlineVulkanBinary;
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
      type = types.nullOr types.str;
      default = null;
      description = "Store path of the built PrismML llama.cpp fork (nix build .#cuda output). NVIDIA hosts.";
      example = "/nix/store/00000000000000000000000000000000-llama-cpp-cuda";
    };

    vulkanBinaryStorePath = mkOption {
      type = types.nullOr types.str;
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
    ternaryNexus
    bit1Nexus
    ternaryForge
    bit1Forge0
    bit1Forge1
    bit1Sentry
    bit1Krash3
  ];
}
