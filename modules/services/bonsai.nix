# Bonsai 27B llama-server deployments
#
# Self-hosted inference across the homelab. Ternary (2-bit, 6.7 GB) runs on
# larger GPUs when not mining; 1-bit (3.9 GB) runs everywhere including CPU.
#
#   Host          GPU(s)                          Ternary port  1-bit port
#   ──────────────────────────────────────────────────────────────────────
#   Zephyr        RTX 3090 (GPU 1) + 3060 Ti (0)  1237          1236
#   Nexus         RTX 3060 Ti                     —             1235
#   Forge         RTX 4060 (GPU 0)                —             8002
#   Sentry        AMD RX 5600 XT (Vulkan)         —             8003
#   krash3        CPU-only                        —             8004
#
# Binary: PrismML llama.cpp fork. Build:
#   cd /tmp/prism-llama-fork
#   NIXPKGS_ALLOW_UNFREE=1 nix build .#cuda   --builders '' --max-jobs 2 --impure
#   NIXPKGS_ALLOW_UNFREE=1 nix build .#vulkan --builders '' --max-jobs 2 --impure
# Models: /models/bonsai/{ternary-27b,1bit-27b,dspark}
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
  prismBinary = pkgs.runCommand "prism-llama-bonsai" {} ''
    mkdir -p $out/bin
    cp -rL ${cfg.binaryStorePath}/bin/llama-server $out/bin/llama-server
    for lib in ${cfg.binaryStorePath}/lib/*.so*; do
      cp -rL "$lib" $out/bin/ 2>/dev/null || true
    done
  '';

  # Optional Vulkan binary for AMD hosts.
  prismVulkanBinary =
    if cfg.vulkanBinaryStorePath != null then
      pkgs.runCommand "prism-llama-bonsai-vulkan" {} ''
        mkdir -p $out/bin
        cp -rL ${cfg.vulkanBinaryStorePath}/bin/llama-server $out/bin/llama-server
        for lib in ${cfg.vulkanBinaryStorePath}/lib/*.so*; do
          cp -rL "$lib" $out/bin/ 2>/dev/null || true
        done
      ''
    else null;

  # Shorthand: 1-bit Bonsai service.
  mk1bitService = { name, desc, port, gpu ? null, extraEnv ? {}, binary ? prismBinary }: {
    systemd.services."bonsai-1bit-${name}" = {
      description = desc;
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = "bonsai";
        RuntimeDirectory = "bonsai-1bit-${name}";
        ExecStart = "${getExe binary} -m ${cfg.onebitModel} --host 0.0.0.0 --port ${toString port} -ngl 99 -fa on -c 0 --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 --alias bonsai-27b-1bit-${name}";
        Restart = "on-failure";
        RestartSec = "10";
        StandardOutput = "journal";
        StandardError = "journal";
        MemoryMax = "6G";
        LimitNOFILE = 65536;
        OOMScoreAdjust = 500;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = ["/run/bonsai-1bit-${name}"];
        ReadOnlyPaths = ["${cfg.onebitModel}"];
      };
      environment = optionalAttrs (gpu != null) { CUDA_VISIBLE_DEVICES = gpu; } // extraEnv;
    };
  };

  # Shorthand: Ternary Bonsai service (6.7 GB, needs >=24 GB VRAM for 262K ctx).
  mkTernaryService = { name, desc, port, gpu, memoryMax ? "20G" }: {
    systemd.services."bonsai-ternary-${name}" = {
      description = desc;
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = "bonsai";
        RuntimeDirectory = "bonsai-ternary-${name}";
        ExecStart = "${getExe cfg.package} -m ${cfg.ternaryModel} --host 0.0.0.0 --port ${toString port} -ngl 99 -fa on -c 0 --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 --jinja --alias ternary-bonsai-27b-${name}";
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
        ReadOnlyPaths = ["${cfg.ternaryModel}" "${cfg.mmproj}"];
      };
      environment = {
        CUDA_VISIBLE_DEVICES = gpu;
        CUDA_CACHE_DISABLE = "1";
      };
    };
  };

  # ── All services, each gated by hostname ──

  # Ternary on zephyr 3090 (GPU 1, 24 GB)
  ternaryZephyr = mkIf (host == "zephyr") (mkTernaryService {
    name = "zephyr"; desc = "Bonsai 27B Ternary — Zephyr RTX 3090 (port 1237)";
    port = 1237; gpu = "1"; memoryMax = "20G";
  });

  # 1-bit on zephyr 3060 Ti (GPU 0, 8 GB)
  bit1Zephyr = mkIf (host == "zephyr") (mk1bitService {
    name = "zephyr"; desc = "Bonsai 27B 1-bit — Zephyr RTX 3060 Ti (port 1236)";
    port = 1236; gpu = "0";
  });

  # 1-bit on nexus 3060 Ti (8 GB) — ternary can also run when miners idle (-c 0 fits ctx to VRAM)
  bit1Nexus = mkIf (host == "nexus") (mk1bitService {
    name = "nexus"; desc = "Bonsai 27B 1-bit — Nexus RTX 3060 Ti (port 1235)";
    port = 1235;
  });

  ternaryNexus = mkIf (host == "nexus") (mkTernaryService {
    name = "nexus"; desc = "Bonsai 27B Ternary — Nexus RTX 3060 Ti (port 1238, when GPU idle)";
    port = 1238; gpu = "0"; memoryMax = "8G";
  });

  # 1-bit on forge 4060 (GPU 0, 8 GB)
  bit1Forge = mkIf (host == "forge") (mk1bitService {
    name = "forge"; desc = "Bonsai 27B 1-bit — Forge RTX 4060 (port 8002)";
    port = 8002; gpu = "0";
  });

  # Ternary on forge 4060 — tight fit (6.7 GB on 8 GB), starts when miners idle
  ternaryForge = mkIf (host == "forge") (mkTernaryService {
    name = "forge"; desc = "Bonsai 27B Ternary — Forge RTX 4060 (port 8005, when GPU idle, tight)";
    port = 8005; gpu = "0"; memoryMax = "8G";
  });

  # 1-bit on sentry AMD via Vulkan
  bit1Sentry = mkIf (host == "sentry" && cfg.vulkanBinaryStorePath != null) (mk1bitService {
    name = "sentry"; desc = "Bonsai 27B 1-bit — Sentry AMD via Vulkan (port 8003)";
    port = 8003; binary = prismVulkanBinary; extraEnv = { GGML_VULKAN_DEVICE = "0"; };
  });

  # 1-bit on krash3 CPU-only (no GPU available)
  bit1Krash3 = mkIf (host == "krash3") (mk1bitService {
    name = "krash3"; desc = "Bonsai 27B 1-bit — krash3 CPU-only (port 8004)";
    port = 8004; extraEnv = {};
  });

in {
  options.services.bonsai = {
    enable = mkEnableOption "Bonsai 27B llama-server inference";

    binaryStorePath = mkOption {
      type = types.str;
      description = "Store path of the built PrismML llama.cpp fork (nix build .#cuda output)";
      example = "/nix/store/00000000000000000000000000000000-llama-cpp-cuda";
    };

    vulkanBinaryStorePath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Store path of the PrismML fork built with Vulkan (AMD/Radeon hosts)";
      example = "/nix/store/xxx-llama-cpp-vulkan-0.0.0";
    };

    package = mkOption {
      type = types.package;
      default = prismBinary;
      description = "PrismML llama.cpp package. Defaults to binaryStorePath wrapper.";
    };

    ternaryModel = mkOption {
      type = types.path;
      default = "/models/bonsai/ternary-27b/Ternary-Bonsai-27B-Q2_0.gguf";
    };

    onebitModel = mkOption {
      type = types.path;
      default = "/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
    };

    dsparkModel = mkOption {
      type = types.nullOr types.path;
      default = "/models/bonsai/dspark/Ternary-Bonsai-27B-dspark-Q4_1.gguf";
    };

    mmproj = mkOption {
      type = types.nullOr types.path;
      default = "/models/bonsai/ternary-27b/Ternary-Bonsai-27B-mmproj-Q8_0.gguf";
    };
  };

  config = mkIf cfg.enable {
    users.users.bonsai = {
      isSystemUser = true;
      group = "bonsai";
      description = "Bonsai 27B inference service";
    };
    users.groups.bonsai = {};
  } // ternaryZephyr // bit1Zephyr // ternaryNexus // bit1Nexus // ternaryForge // bit1Forge // bit1Sentry // bit1Krash3;
}
