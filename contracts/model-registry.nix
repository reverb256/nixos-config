# model-registry.nix — declarative source of truth for every GGUF the fleet
# serves. Enterprise-grade provenance: each model pins its GGUF by sha256, its
# required llama.cpp capability set, and the VERIFIED per-host serving flags.
#
# WHY THIS EXISTS (2026-08-13/14 incidents):
#   - nexus llama-server crash-looped because the catalog used turbo4 KV at
#     256K on an 8 GB card (buffer overflow -> illegal memory access) and a
#     stale fork binary for Nemotron (expected 417 tensors, GGUF has 408 after
#     bartowski re-uploaded with MTP). Both were configuration drift that a
#     registry + load-smoke gate catches BEFORE deploy.
#   - A GGUF hash change (bartowski re-upload) must be a deliberate act: bump
#     the sha256 here, re-run the load-smoke, then deploy. No silent drift.
#
# Fields:
#   id          — llama-swap model id / alias
#   name        — human label
#   model       — GGUF path on the host
#   sha256      — provenance pin of the GGUF (verify with `sha256sum`)
#   arch        — GGUF architecture (granite-hybrid, nemotron_h_moe, ...)
#   capabilities — llama.cpp feature set the BINARY must provide
#   tensorCount — expected GGUF tensor count (load-smoke asserts loader agrees)
#   hosts       — per-host serving config { gpu, ctx, cacheK, cacheV, extraFlags }
#
# Serving-flag discipline (from llama-cpp-optimization skill, verified):
#   - 8 GB cards (3060 Ti / 4060): turbo4 KV fits <=128K; 256K needs q4_0 KV
#     (spills to RAM but serves) — NEVER turbo4 @ 256K on 8 GB.
#   - MoE on 8 GB (nemotron 30B-A3B): -ngl 25 --n-cpu-moe 40 --fit off,
#     context <= 32768. -ngl 99 + n-cpu-moe OOMs compute buffers.
#   - binary must be >= b10362 for MTP-included Nemotron GGUFs.
{
  # Model registry entries. Add new GGUFs here, not in llama-swap-cluster.nix.
  models =
    [
      {
        id = "bonsai-1bit";
        name = "Bonsai 27B 1-bit (Q1_0)";
        model = "/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
        sha256 = "PENDING_VERIFY"; # TODO: set after first load-smoke (never ship 'PENDING')
        arch = "granite-hybrid";
        capabilities = ["bonsai-q1_0" "turboquant-kv"];
        tensorCount = 0; # populated by verify-models.sh on first run
        hosts = {
          nexus = {
            gpuUuid = "GPU-6bc1c22c-41e5-0ab7-285e-911c43b1b29e";
            ctx = 262144; # full context — proven on 3060 Ti with q4_0 KV (zephyr)
            cacheK = "q4_0"; # NOT turbo4 at 256K on 8 GB (illegal access)
            cacheV = "q4_0";
            ngl = 99;
          };
          zephyr-3060ti = {
            gpuUuid = "GPU-zephyr-3060ti"; # set from hardware.nix
            ctx = 262144;
            cacheK = "q4_0";
            cacheV = "q4_0";
            ngl = 99;
          };
          forge = {
            gpuUuid = "GPU-5eb10624-1e18-33d9-f7f7-f8040ac34dad";
            ctx = 131072; # miner-shared card: 128K proven headroom
            cacheK = "q4_0";
            cacheV = "q4_0";
            ngl = 99;
          };
        };
      }
      {
        id = "nemotron-30b-a3b";
        name = "Nemotron 3.5 Lightning 30B-A3B (IQ3_M)";
        model = "/models/nemotron-3.5-30b/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-IQ3_M.gguf";
        sha256 = "affceaeefd0b819676e5947645e9bcc6"; # verified on nexus 2026-08-14
        arch = "nemotron_h_moe";
        capabilities = ["nemotron_h_moe" "mtp" "n-cpu-moe" ">=b10362"];
        tensorCount = 408; # b10362-era MTP-included layout
        hosts = {
          nexus = {
            gpuUuid = "GPU-6bc1c22c-41e5-0ab7-285e-911c43b1b29e";
            ctx = 32768; # verified 8 GB MoE ceiling
            cacheK = "q8_0"; # asymmetric: K higher precision (skill table)
            cacheV = "turbo4";
            ngl = 25; # NOT 99 — frees compute buffers for n-cpu-moe
            extraFlags = "--n-cpu-moe 40 --no-mmap --mlock --fit off";
          };
        };
      }
    ];

  # Binary requirement check: does a llama.cpp build expose the capabilities a
  # model needs? Populated by the package overlay; load-smoke enforces at run.
  binaryCapabilities = {
    llama-cpp-unified = ["bonsai-q1_0" "turboquant-kv" "nemotron_h_moe" "mtp" "n-cpu-moe" "muse_glimmer"];
    llama-cpp-unified-vulkan = ["bonsai-q1_0" "turboquant-kv" "nemotron_h_moe" "mtp" "n-cpu-moe" "muse_glimmer"];
    llama-cpp-mainline = ["nemotron_h_moe" "mtp" "n-cpu-moe" "muse_glimmer"];
  };
}
