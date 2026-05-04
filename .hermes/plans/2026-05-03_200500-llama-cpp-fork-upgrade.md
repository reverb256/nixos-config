# LLAMA.CPP FORK UPGRADE PLAN

## Goal
Upgrade the cluster llama.cpp inference stack to incorporate TriAttention KV eviction, DFlash DDtree speculative decoding with spec-prefill, and proper model-profile switching.

## Current Context

### Fork and Build
- Fork: spiritbuun/buun-llama-cpp pinned at aecbbd5d
- Nix package: /etc/nixos/packages/llama-cpp-turboquant.nix
- Build: CUDA sm_86, Zen3, Flash Attention, TurboQuant KV (turbo2/3/4+TCQ)
- TriAttention patch exists (142KB, 3549 lines) but NOT applied
- All llama deployments scaled to 0 currently

### Models on Disk
- Qwen3.6-27B Q4_K_M (16GB) -- DFlash target
- dflash-draft-3.6-q8_0 (1.8GB) -- DFlash draft
- Qwen3.6-35B-A3B UD-IQ3_S (13GB) -- MoE plain AR only
- Qwen3.6-35B-A3B-DFlash-q8_0 (491MB) -- vLLM only, not usable in GGUF
- carnice-v2-27b Q4_K_M (16GB) -- creative DFlash target

### Key Constraints
- nvidia-container-runtime remaps GPU indices (host GPU 1 = container GPU 0)
- All inference via kubectl scale, never manual llama-server
- MoE + speculative = NET NEGATIVE on single 3090 (expert saturation)
- DFlash on 27B dense = 3.43x speedup (129.5 tok/s vs 37.8 tok/s)
- TriAttention + TurboQuant = ~40x effective context
- Luce spec-prefill = 10x faster TTFT

---

## Phase 1: Sync Spiritbuun Fork (~30 min)
1. Check latest spiritbuun commit vs current pin aecbbd5d
2. Update rev + hash in /etc/nixos/packages/llama-cpp-turboquant.nix
3. nix build, verify binary features (turbo4, dflash hooks, FA)
4. Rollout test: scale deployment, verify GPU + model load

Files: /etc/nixos/packages/llama-cpp-turboquant.nix
Risks: spiritbuun breaking changes; hash mismatch loop

## Phase 2: Apply TriAttention Patch (~1-2 hrs)
1. Port triattention.patch to updated fork (resolve conflicts in common/arg.cpp, common/common.h, src/llama.cpp, include/llama.h)
2. Add patches = [ ./triattention.patch ] to nix derivation
3. Build, verify triattention symbols
4. Test deployment with --triattention-budget 0.05 --triattention-window 2048
5. Verify KV eviction in logs on 8K+ context

Files: /etc/nixos/packages/llama-cpp-turboquant.nix
Risks: Patch conflicts with TurboQuant mods; TriAttention + turbo4 unknown interaction

## Phase 3: Build Luce DFlash Binary (~2-3 hrs)
1. Create /etc/nixos/packages/llama-cpp-dflash.nix
   - Source: Luce-Org/llama.cpp branch luce-dflash
   - Fetch BSA submodule deps/Block-Sparse-Attention
   - Flags: GGML_CUDA=ON, DDFLASH27B_ENABLE_BSA=ON, sm_86, Zen3
2. Create /etc/nixos/packages/dflash-server.nix (server_tools.py wrapper with FastAPI)
3. Uncomment in /etc/nixos/overlay.nix
4. Download Qwen3-0.6B spec-prefill drafter GGUF
5. Create K8s deployment llama-server-dflash-3090 in llama-servers.nix
6. Test: expect ~78-129 tok/s decode, 10x TTFT on long prompts

Files: NEW llama-cpp-dflash.nix, dflash-server.nix; MODIFY overlay.nix, llama-servers.nix
Risks: BSA submodule in nix sandbox; no TurboQuant in DFlash fork; CMake structure differs

## Phase 4: Profile Switching and Gateway Integration (~1 hr)
1. Three 3090 profiles (mutually exclusive, kubectl scale):
   - dense-dflash: Qwen3.6-27B + DFlash + spec-prefill (port 1239)
   - moe-plain: Qwen3.6-35B-A3B + TriAttention + TurboQuant (port 1237)
   - creative-dflash: carnice-v2-27b + DFlash (new port)
2. Update gateway routing with all three backends
3. Extend mining-coordinator for inference profile switching
4. Keep 3060Ti vLLM Qwen3.5-2B-AWQ unchanged

Files: llama-servers.nix, gateway config, mining coordinator

## Open Questions
1. Switch to TheTom directly if spiritbuun stale? (Loses dflash hooks)
2. DFlash fork has no TurboQuant -- use q8_0 KV instead of turbo4?
3. Qwen3-0.6B spec-prefill drafter available as pre-built GGUF?
4. TriAttention eviction works with TurboQuant-compressed KV?
5. Built-in llama.cpp server vs server_tools.py for tool calling?

## Rollback
Each phase independent: revert nix changes, comment overlay, scale to 0.
