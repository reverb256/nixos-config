# Bonsai 27B llama-server deployments
#
# Self-hosted inference endpoints for The Echo Chamber game (see ~/Projects/Game).
#   - Zephyr RTX 3090 (GPU 1): Ternary-Bonsai-27B (Q2_0_g128, 6.7 GB) on port 1237
#   - Zephyr RTX 3060 Ti (GPU 0): 1-bit Bonsai-27B (Q1_0, 3.6 GB) on port 1236
#   - Nexus RTX 3060 Ti: 1-bit Bonsai-27B on port 1235
#   - Forge RTX 4060 (GPU 0): 1-bit Bonsai-27B on port 8002
#   - Sentry RX 5600 XT: 1-bit Bonsai-27B via Vulkan on port 8003
#
# The PrismML fork binary is REQUIRED for the ternary variant (ggml type 42).
# Build it with:
#   cd /tmp/prism-llama-fork && NIXPKGS_ALLOW_UNFREE=1 nix build .#cuda --builders '' --max-jobs 2 --impure
# For Vulkan (AMD/Sentry):
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

  # Wrap the PrismML fork CUDA binary into a package the module can consume.
  prismBinary = pkgs.runCommand "prism-llama-bonsai" {} ''
    mkdir -p $out/bin
    cp -rL ${cfg.binaryStorePath}/bin/llama-server $out/bin/llama-server
    for lib in ${cfg.binaryStorePath}/lib/*.so*; do
      cp -rL "$lib" $out/bin/ 2>/dev/null || true
    done
  '';

  # Optional Vulkan binary for AMD hosts.
  prismVulkanBinary = if cfg.vulkanBinaryStorePath != null then
    pkgs.runCommand "prism-llama-bonsai-vulkan" {} ''
      mkdir -p $out/bin
      cp -rL ${cfg.vulkanBinaryStorePath}/bin/llama-server $out/bin/llama-server
      for lib in ${cfg.vulkanBinaryStorePath}/lib/*.so*; do
        cp -rL "$lib" $out/bin/ 2>/dev/null || true
      done
    ''
  else null;

  # Shorthand: build a service attrset for a 1-bit Bonsai instance.
  mk1bitService = { name, desc, port, gpu ? null, extraEnv ? {}, binary ? prismBinary }: {
    description = desc;
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      User = "bonsai";
      RuntimeDirectory = "bonsai-${name}";
      ExecStart = "${getExe binary} -m ${cfg.onebitModel} --host 0.0.0.0 --port ${toString port} -ngl 99 -fa on -c 0 --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 --alias bonsai-27b-${name}";
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
      ReadWritePaths = ["/run/bonsai-${name}"];
      ReadOnlyPaths = ["${cfg.onebitModel}"];
    };
    environment = optionalAttrs (gpu != null) { CUDA_VISIBLE_DEVICES = gpu; } // extraEnv;
  };

  # All possible services; each is gated by hostname below.
  ternaryZephyr = mkIf (host == "zephyr") {
    systemd.services.bonsai-ternary-zephyr = {
      description = "Bonsai 27B Ternary — Zephyr RTX 3090 (port 1237)";
      after = ["network.target" "systemd-udev-settle.service"];
      wants = ["systemd-udev-settle.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = "bonsai";
        RuntimeDirectory = "bonsai-ternary";
        ExecStart = "${getExe cfg.package} -m ${cfg.ternaryModel} --host 0.0.0.0 --port 1237 -ngl 99 -fa on -c 0 --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 --jinja --alias ternary-bonsai-27b${lib.optionalString (cfg.mmproj != null) " --mmproj ${cfg.mmproj}"}";
        Restart = "on-failure";
        RestartSec = "10";
        StandardOutput = "journal";
        StandardError = "journal";
        MemoryMax = "20G";
        LimitNOFILE = 65536;
        OOMScoreAdjust = 500;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = ["/run/bonsai-ternary"];
        ReadOnlyPaths = ["${cfg.ternaryModel}" "${cfg.mmproj}"];
      };
      environment = {
        CUDA_VISIBLE_DEVICES = "1";
        CUDA_CACHE_DISABLE = "1";
      };
    };
  };

  bit1Zephyr = mkIf (host == "zephyr") (
    mk1bitService {
      name = "1bit-zephyr";
      desc = "Bonsai 27B 1-bit — Zephyr RTX 3060 Ti (port 1236)";
      port = 1236;
      gpu = "0";
    }
  );

  bit1Nexus = mkIf (host == "nexus") (
    mk1bitService {
      name = "1bit-nexus";
      desc = "Bonsai 27B 1-bit — Nexus RTX 3060 Ti (port 1235)";
      port = 1235;
    }
  );

  bit1Forge = mkIf (host == "forge") (
    mk1bitService {
      name = "1bit-forge";
      desc = "Bonsai 27B 1-bit — Forge RTX 4060 (port 8002)";
      port = 8002;
      gpu = "0";
    }
  );

  bit1Sentry = mkIf (host == "sentry" && cfg.vulkanBinaryStorePath != null) (
    mk1bitService {
      name = "1bit-sentry";
      desc = "Bonsai 27B 1-bit — Sentry AMD RX 5600 XT via Vulkan (port 8003)";
      port = 8003;
      binary = prismVulkanBinary;
      extraEnv = { GGML_VULKAN_DEVICE = "0"; };
    }
  );

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
      description = "Store path of the PrismML fork built with Vulkan (nix build .#vulkan); used on AMD/Radeon hosts";
      example = "/nix/store/xxx-llama-cpp-vulkan-0.0.0";
    };

    package = mkOption {
      type = types.package;
      default = prismBinary;
      description = "PrismML llama.cpp package (llama-server binary). Defaults to binaryStorePath wrapper.";
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
  } // ternaryZephyr // bit1Zephyr // bit1Nexus // bit1Forge // bit1Sentry // bit1Krash3;
}

  bit1Krash3 = mkIf (host == "krash3") (
    mk1bitService {
      name = "1bit-krash3";
      desc = "Bonsai 27B 1-bit — krash3 CPU-only (port 8004)";
      port = 8004;
      extraEnv = {}; # no GPU, all CPU
    }
  );
