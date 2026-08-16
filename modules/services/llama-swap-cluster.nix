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
  # models: list of { id; name; model; gpuUuid; vkDevice?; ctx?; fa?; cacheK?; cacheV?; extraFlags?; binary? }
  #
  # Each model is emitted as a 2-space-indented YAML block, built from explicit
  # string lines (no nested ''-string indentation stripping) so the emitted YAML
  # stays correctly nested regardless of the module's surrounding indentation.
  # (\\${PORT} is llama-swap's own runtime substitution, escaped from Nix.)
  modelYaml = m:
    let bin = m.binary or unifiedLlama; in
    concatStringsSep "\n" [
      "  \"${m.id}\":"
      "    name: \"${m.name}\""
      "    cmd: |"
      "      /run/current-system/sw/bin/setsid env -i \\"
      "        HOME=/home/j_kro USER=j_kro \\"
      "        PATH=/run/current-system/sw/bin:/usr/bin:/bin \\"
      "        LD_LIBRARY_PATH=${bin}/lib:/run/opengl-driver/lib \\"
      "        ${
        if m.vkDevice or null == null
        then "CUDA_VISIBLE_DEVICES=${m.gpuUuid} \\"
        else "GGML_VULKAN_DEVICE=${m.vkDevice} \\"
      }"
      "        GGML_CUDA_ENABLE_UNIFIED_MEMORY=0 \\"
      "        ${bin}/bin/llama-server \\"
      "        -m ${m.model} \\"
      "        --host 127.0.0.1 --port \${PORT} -ngl 99 -fa ${m.fa or "on"} -c ${toString (m.ctx or 262144)} \\"
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
          # CRITICAL (2026-08-14): startPort must NOT equal the proxy --listen
          # port. Models bind startPort+idx; the proxy owns its own listen port.
          # nexus listen=21759 / startPort=21760 (models 21760+);
          # forge  listen=21763 / startPort=21761 (models 21761+);
          # sentry listen=21764 / startPort=21762 (models 21762+).
          # Equal ports -> every model spawn dies: "couldn't bind HTTP server
          # socket, port: N" -> llama-swap cooldown -> 429 -> crash loop.
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
              name = "Bonsai 1bit 256k q4_0";
              model = "/data/shared/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
              gpuUuid = "GPU-6bc1c22c-41e5-0ab7-285e-911c43b1b29e";
              # 2026-08-14: KV fix for Crash A. mkCatalog defaults cacheK/V to
              # turbo4; on nexus 8 GB that overflowed @ 262144 -> illegal access.
              # q4_0/q4_0 matches zephyr (serves, spills to RAM). Keep turbo4 only
              # on >=24 GB cards (zephyr 3090 ternary uses q8_0, not turbo4).
              cacheK = "q4_0";
              cacheV = "q4_0";
            }
            {
              id = "nemotron-30b-a3b";
              name = "Nemotron 3.5 Lightning 30B-A3B (IQ3_M)";
              model = "/data/shared/models/nemotron-3.5-30b/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-IQ3_M.gguf";
              gpuUuid = "GPU-6bc1c22c-41e5-0ab7-285e-911c43b1b29e";
              ctx = 262144;
              # 2026-08-15 (FIX): the default unified turboquant build
              # (fca3093) fails this model with "expected 417, got 408"
              # tensors (MTP tensor check — the skill-documented 417-vs-408
              # blocker). The PLAIN nixpkgs llama-cpp build (2026-08-12,
              # verified loads on nexus) has no MTP expectation. Use it for
              # this model; turboquant stays for Bonsai.
              binary = pkgs.llama-cpp;
              # Verified recipe (2026-08-13). --fit off + -ngl 25 are NOT
              # optional: without them the MoE offload OOMs on 8 GB.
              extraFlags = "--n-cpu-moe 40 --no-mmap --mlock --cache-type-k turbo4 --cache-type-v turbo3 --fit off -ngl 25";
            }
          ];
        };
      }
      (mkService {
        name = "nexus";
        port = 21759; # proxy listen; models bind 21760+ (startPort)
        yamlFile = "nexus.yaml";
      })
      # Workload registry: gguf entries (menu load/unload via swap). Port =
      # startPort+idx (21760 bonsai, 21761 nemotron). Menu reads the JSON at
      # runtime over SSH — no menu edit when this catalog changes.
      {
        services.gpu-workload-registry.workloads.nexus = [
          {
            id = "bonsai-1bit";
            name = "Bonsai 1bit (Nexus)";
            gpuLabel = "3060 Ti";
            kind = "gguf";
            port = 21760;
            swapId = "bonsai-1bit";
            swapPort = 21759;
            alwaysOn = false;
          }
          {
            id = "nemotron-30b-a3b";
            name = "Nemotron 30B (Nexus)";
            gpuLabel = "3060 Ti";
            kind = "gguf";
            port = 21761;
            swapId = "nemotron-30b-a3b";
            swapPort = 21759;
            alwaysOn = false;
          }
        ];
      }
    ]))

    # ── forge: 4060s are 100% mining since 2026-08-15 — NO llama-swap catalog ──
    # The 5700 XT pair (bonsai-1bit-forge-vk0/vk1, ports 8007/8008) serves
    # Bonsai via DIRECT systemd units (RDNA1 env baked in: MAX_NODES=1,
    # nogttspill, TURBO_AUTO_ASYMMETRIC=0, -fa off). The catalog spawns with a
    # clean env and cannot carry those fixes — a swap model on a mining 4060
    # would squat compute. The registry lists the two direct units instead.
    # (services.llama-swap-cluster.enable = false on forge — see host config.)

    # ── sentry: AMD RX 5600 XT (Vulkan) — Gemma 4 E2B (replaces Bonsai 1-bit) ──
    (mkIf (host == "sentry" && cfg.enable) (mkMerge [
      {
        environment.etc = mkCatalog {
          fileName = "sentry.yaml";
          models = [
            {
              id = "gemma-e2b";
              name = "Gemma 4 E2B 128k";
              model = "/storage/models/gemma4/gemma-4-E2B-it-Q4_K_M.gguf";
              vkDevice = "0";
              ctx = 131072;
              fa = "off"; # RDNA1: -fa on costs 10x decode (2026-08-14, measured 84 t/s)
              cacheK = "q8_0";
              cacheV = "f16"; # quantized V requires FA
            }
          ];
        };
      }
      (mkService {
        name = "sentry";
        port = 21764; # proxy listen; models bind 21762+ (startPort)
        yamlFile = "sentry.yaml";
      })
      {
        services.gpu-workload-registry.workloads.sentry = [
          {
            id = "gemma-e2b";
            name = "Gemma 4 E2B (Sentry)";
            gpuLabel = "5600 XT";
            kind = "gguf";
            port = 21762;
            swapId = "gemma-e2b";
            swapPort = 21764;
            alwaysOn = false;
          }
        ];
      }
    ]))
  ];
}
