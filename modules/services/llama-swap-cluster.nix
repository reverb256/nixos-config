# llama-swap cluster services — llama-swap across the board
#
# Runs the llama-swap model-swapping proxy on every GPU host, using the SAME
# unified llama.cpp binary as zephyr (packages.llama-cpp-unified: retroheim
# turboquant — PrismML Bonsai + TurboQuant KV + CUDA + Vulkan).
#
#   Host    GPU               llama-swap port   catalog
#   nexus   RTX 3060 Ti 8G    21760             Bonsai 1bit (Q1_0)
#   forge   RTX 4060 8G       21761             Bonsai 1bit (Q1_0)
#   sentry  AMD 5600 XT 6G    21762             Bonsai 1bit (Q1_0, Vulkan)
#
# Each host's bonsai.nix systemd unit still serves the always-on 1-bit on its
# dedicated port (1235/8002/8003); llama-swap adds the swappable OpenAI-style
# endpoint on top. TTL discipline: on-demand (globalTTL 600) so a cluster model
# unloads when idle, freeing VRAM for the miner + the always-on Bonsai.
#
# Host-gated via mkIf (host == ...). The serving binary is the unified package
# (never a raw store path — GC-safe, colmena-copied).
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.llama-swap-cluster;
  host = config.networking.hostName;

  unifiedLlama = if host == "sentry" then pkgs.llama-cpp-unified-vulkan else pkgs.llama-cpp-unified;
  llamaSwap = pkgs.llama-swap;

  # Write a llama-swap catalog yaml for one host (system-level, /etc/llama-swap).
  mkCatalog = { fileName, modelPath, gpuUuid, extraEnv ? { }, ctx ? "262144", cacheK ? "turbo4", cacheV ? "turbo4", vkDevice ? null }: {
    "llama-swap/${fileName}" = {
      text = ''
        logLevel: info
        logTimeFormat: rfc3339
        healthCheckTimeout: 300
        globalTTL: 600
        startPort: ${if fileName == "nexus.yaml" then "21760" else if fileName == "forge.yaml" then "21761" else "21762"}
        models:
          "bonsai-1bit":
            name: "Bonsai 1bit 256k Turbo4"
            cmd: |
              setsid env -i \
                HOME=/home/j_kro USER=j_kro \
                PATH=/run/current-system/sw/bin:/usr/bin:/bin \
                LD_LIBRARY_PATH=${unifiedLlama}/lib:/run/opengl-driver/lib \
                ${optionalString (vkDevice == null) "CUDA_VISIBLE_DEVICES=${gpuUuid} \\"}
                ${optionalString (vkDevice != null) "GGML_VULKAN_DEVICE=${vkDevice} \\"}
                GGML_CUDA_ENABLE_UNIFIED_MEMORY=0 \
                ${unifiedLlama}/bin/llama-server \
                -m ${modelPath} \
                --host 127.0.0.1 --port ''${PORT} -ngl 99 -fa on -c ${ctx} \
                --cache-type-k ${cacheK} --cache-type-v ${cacheV} --fit off \
                --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 --jinja --parallel 1 \
                --alias bonsai-27b-1bit-${fileName}
            aliases:
              - "bonsai-1bit"
            env:
              - "LLAMA_PORT="
            ttl: 600
            unloadTimeout: 15
      '';
    };
  };

  mkService = { name, port, yamlFile }: {
    systemd.services."llama-swap-${name}" = {
      description = "llama-swap — ${name} (unified turboquant llama.cpp)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "j_kro";
        ExecStart = "${llamaSwap}/bin/llama-swap --config /etc/llama-swap/${yamlFile} --listen 127.0.0.1:${toString port}";
        Restart = "on-failure";
        RestartSec = "5";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ port ];
  };
in {
  options.services.llama-swap-cluster = {
    enable = mkEnableOption "llama-swap cluster services (llama-swap across the board)";
  };

  config = mkMerge [
    # ── nexus: RTX 3060 Ti (CUDA) ──
    (mkIf (host == "nexus" && cfg.enable) (mkMerge [
      { environment.etc = mkCatalog {
        fileName = "nexus.yaml";
        modelPath = "/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
        gpuUuid = "GPU-6bc1c22c-41e5-0ab7-285e-911c43b1b29e";
      }; }
      (mkService { name = "nexus"; port = 21760; yamlFile = "nexus.yaml"; })
    ]))

    # ── forge: RTX 4060 (CUDA0) ──
    (mkIf (host == "forge" && cfg.enable) (mkMerge [
      { environment.etc = mkCatalog {
        fileName = "forge.yaml";
        modelPath = "/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
        gpuUuid = "GPU-5eb10624-1e18-33d9-f7f7-f8040ac34dad";
      }; }
      (mkService { name = "forge"; port = 21761; yamlFile = "forge.yaml"; })
    ]))

    # ── sentry: AMD RX 5600 XT (Vulkan) — /srv/models, smaller ctx ──
    (mkIf (host == "sentry" && cfg.enable) (mkMerge [
      { environment.etc = mkCatalog {
        fileName = "sentry.yaml";
        modelPath = "/srv/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
        gpuUuid = "";
        vkDevice = "0";
        ctx = "8192";
        cacheK = "q4_0";
        cacheV = "q4_0";
      }; }
      (mkService { name = "sentry"; port = 21762; yamlFile = "sentry.yaml"; })
    ]))
  ];
}
