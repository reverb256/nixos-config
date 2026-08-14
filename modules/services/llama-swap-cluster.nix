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
with lib; let
  cfg = config.services.llama-swap-cluster;
  host = config.networking.hostName;

  unifiedLlama =
    if host == "sentry"
    then pkgs.llama-cpp-unified-vulkan
    else pkgs.llama-cpp-unified;
  llamaSwap = pkgs.llama-swap;

  # Write a llama-swap catalog yaml for one host (system-level, /etc/llama-swap).
  # models: list of { id; name; model; gpuUuid; vkDevice?; ctx?; cacheK?; cacheV?; extraFlags? }
  #
  # Each model is emitted as a 2-space-indented YAML block, built from explicit
  # string lines (no nested ''-string indentation stripping) so the emitted YAML
  # stays correctly nested regardless of the module's surrounding indentation.
  # (\${PORT} is llama-swap's own runtime substitution, escaped from Nix.)
  modelYaml = m:
    concatStringsSep "\n" [
      "  \"${m.id}\":"
      "    name: \"${m.name}\""
      "    cmd: |"
      "      setsid env -i \\"
      "        HOME=/home/j_kro USER=j_kro \\"
      "        PATH=/run/current-system/sw/bin:/usr/bin:/bin \\"
      "        LD_LIBRARY_PATH=${unifiedLlama}/lib:/run/opengl-driver/lib \\"
      "        ${
        if m.vkDevice or null == null
        then "CUDA_VISIBLE_DEVICES=${m.gpuUuid} \\"
        else "GGML_VULKAN_DEVICE=${m.vkDevice} \\"
      }"
      "        GGML_CUDA_ENABLE_UNIFIED_MEMORY=0 \\"
      "        ${unifiedLlama}/bin/llama-server \\"
      "        -m ${m.model} \\"
      "        --host 127.0.0.1 --port \${PORT} -ngl 99 -fa on -c ${toString (m.ctx or 262144)} \\"
      "        ${
        if m.extraFlags or "" == ""
        then "--cache-type-k ${m.cacheK or "turbo4"} --cache-type-v ${m.cacheV or "turbo4"} --fit off \\"
        else "${m.extraFlags} \\"
      }"
      "        --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 --jinja --parallel 1 \\"
      "        --alias ${m.id}"
      "    aliases:"
      "      - \"${m.id}\""
      "    env:"
      "      - \"LLAMA_PORT=\""
      "    ttl: 600"
      "    unloadTimeout: 15"
    ];

  mkCatalog = {
    fileName,
    models,
  }: {
    "llama-swap/${fileName}" = {
      text =
        ''
          logLevel: info
          logTimeFormat: rfc3339
          healthCheckTimeout: 300
          globalTTL: 600
          startPort: ${
            if fileName == "nexus.yaml"
            then "21760"
            else if fileName == "forge.yaml"
            then "21761"
            else "21762"
          }
          models:
        ''
        + concatMapStringsSep "\n" modelYaml models
        + "\n";
    };
  };

  mkService = {
    name,
    port,
    yamlFile,
  }: {
    systemd.services."llama-swap-${name}" = {
      description = "llama-swap — ${name} (unified turboquant llama.cpp)";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
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
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [port];
  };
in {
  options.services.llama-swap-cluster = {
    enable = mkEnableOption "llama-swap cluster services (llama-swap across the board)";
  };

  config = mkMerge [
    # ── nexus: RTX 3060 Ti (CUDA) — Bonsai 1bit (always-on) + Nemotron 30B-A3B
    #    MoE via --n-cpu-moe (concurrent with miner; experts stream from RAM).
    #    VERIFIED 2026-08-13 on the unified (turboquant) binary:
    #      IQ3_M + -ngl 25 --n-cpu-moe 40 --no-mmap --mlock --fit off
    #      -> loads on 8 GB alongside gamescope/ComfyUI/miner (6.5 GB VRAM),
    #      6.9 tok/s, generation verified. CRITICAL: --fit off is REQUIRED
    #      with --n-cpu-moe (fit planner aborts: "tensor_buft_overrides
    #      already set"); --split-mode row BREAKS single-GPU; -ngl 25 (not 99)
    #      is what frees room for compute buffers. turbo4/turbo3 KV compresses
    #      the cache so 262K ctx fits while the miner holds the card.
    #    llama-swap unloads Bonsai first when Nemotron loads (unload-first swap).
    (mkIf (host == "nexus" && cfg.enable) (mkMerge [
      {
        environment.etc = mkCatalog {
          fileName = "nexus.yaml";
          models = [
            {
              id = "bonsai-1bit";
              name = "Bonsai 1bit 256k Turbo4";
              model = "/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
              gpuUuid = "GPU-6bc1c22c-41e5-0ab7-285e-911c43b1b29e";
            }
            {
              id = "nemotron-30b-a3b";
              name = "Nemotron 3.5 Lightning 30B-A3B (IQ3_M)";
              model = "/models/nemotron-3.5-30b/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-IQ3_M.gguf";
              gpuUuid = "GPU-6bc1c22c-41e5-0ab7-285e-911c43b1b29e";
              ctx = 262144;
              # Verified recipe (2026-08-13). --fit off + -ngl 25 are NOT
              # optional: without them the MoE offload OOMs on 8 GB.
              extraFlags = "--n-cpu-moe 40 --no-mmap --mlock --cache-type-k turbo4 --cache-type-v turbo3 --fit off -ngl 25";
            }
          ];
        };
      }
      (mkService {
        name = "nexus";
        port = 21760;
        yamlFile = "nexus.yaml";
      })
    ]))

    # ── forge: RTX 4060 (CUDA0) — Bonsai 1bit only (both GPUs miner-committed) ──
    (mkIf (host == "forge" && cfg.enable) (mkMerge [
      {
        environment.etc = mkCatalog {
          fileName = "forge.yaml";
          models = [
            {
              id = "bonsai-1bit";
              name = "Bonsai 1bit 256k Turbo4";
              model = "/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
              gpuUuid = "GPU-5eb10624-1e18-33d9-f7f7-f8040ac34dad";
            }
          ];
        };
      }
      (mkService {
        name = "forge";
        port = 21761;
        yamlFile = "forge.yaml";
      })
    ]))

    # ── sentry: AMD RX 5600 XT (Vulkan) — /srv/models, smaller ctx ──
    (mkIf (host == "sentry" && cfg.enable) (mkMerge [
      {
        environment.etc = mkCatalog {
          fileName = "sentry.yaml";
          models = [
            {
              id = "bonsai-1bit";
              name = "Bonsai 1bit 8k q4_0";
              model = "/srv/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
              vkDevice = "0";
              ctx = 8192;
              cacheK = "q4_0";
              cacheV = "q4_0";
            }
          ];
        };
      }
      (mkService {
        name = "sentry";
        port = 21762;
        yamlFile = "sentry.yaml";
      })
    ]))
  ];
}
