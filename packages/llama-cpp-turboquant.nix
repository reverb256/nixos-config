# llama-cpp-turboquant — unified fleet binary (all archs + TurboQuant KV + web UI)
#
# Consumes TheTom/llama-cpp-turboquant (pinned flake input llama-cpp-turboquant
# at rev fca3093c "Merge PR #283 from jasstrong/tq3-fused-hip"). One tree with:
#   - TurboQuant KV: turbo2/3/4 + TQ3_1S/TQ4_1S weight quants (per TheTom's docs
#     turbo cache types "become available automatically once the matching backend
#     is compiled in" — no extra cmake flag needed)
#   - ALL fleet archs: Bonsai (granite-hybrid Q1_0/Q2_0), Nemotron Lightning
#     (nemotron_h_moe), Muse Glimmer (muse_glimmer), DSpark draft, n-cpu-moe
#   - Web UI (LLAMA_BUILD_WEBUI, built locally by the fork's own package.nix)
#
# This SUPERSEDES retroheim/prism-ml-llama.cpp (176bc4f): retroheim was an older
# snapshot that lacked nemotron_h_moe + muse_glimmer (stalled on the Nemotron
# 30B tensor set, 408 vs 417) and its CUDA+Vulkan build hit the FA_COOPMAT2
# shader-gen bug. TheTom fca3093 already restructured the coopmat2 flash-attn
# block (no per-type CREATE_FA(..., FA_COOPMAT2, _cm2) registrations remain) —
# no patch needed.
#
# We build ONE binary with BOTH CUDA and Vulkan backends:
#   - CUDA:  zephyr 3090/3060 Ti, nexus 3060 Ti, forge 4060s (sm_86, sm_89)
#   - Vulkan: sentry AMD RX 5600 XT (Navi 10) — llama.cpp dispatches per-device
# The derivation delegates to the fork's own .devops/nix/package.nix (standard
# llama.cpp recipe with useCuda/useVulkan toggles) via callPackage — we do NOT
# duplicate the build recipe.
{
  lib,
  pkgs,
  llama-cpp-turboquant,
  useCuda ? true,
  ...
}:
let
  # NO IFD: import the fork's package.nix directly from the flake input path
  # (a plain source path, not a derivation). The previous version did
  #   forkSource = pkgs.applyPatches { ... };
  #   packageNix = "${forkSource}/.devops/nix/package.nix";
  # which string-interpolates a DERIVATION into a path -> import-from-
  # derivation. That made `nix flake check --no-build` fail on a cold store
  # ("...-llama-cpp-turboquant-fca3093-rerank.drv did not exist in the store
  # during evaluation") and blocked every nixpkgs bump (PR #701, issue #713).
  # The rerank patch is now applied at BUILD time via overrideAttrs.patches
  # below (equivalent result: same patch on the same tree).
  packageNix = "${llama-cpp-turboquant}/.devops/nix/package.nix";
in
let
  # The fork's package.nix at the pinned rev (main-qwen35 @ 329c616c) does NOT
  # accept a cmakeFlags argument — it hardcodes its own flag list (GGML_NATIVE
  # already false). Pass only the flags it accepts via callPackage, then append
  # the x86-64-v3 CPU tuning with overrideAttrs (2026-08-16): all fleet CPUs
  # are AVX2-capable (zephyr 5950X, nexus 3900X, sentry 1700, forge i5-9500).
  # The CPU-side hot paths (prompt eval, rerank head, embeddings) get the
  # AVX2/FMA uplift. CUDA/Vulkan backends are compiled separately.
  base = pkgs.callPackage packageNix {
    inherit useCuda;
    useVulkan = true;
    useBlas = false;
    useMpi = false;
    useRocm = false;
    useRpc = false;
    useWebUi = true; # build tools/ui so the llama.cpp webpage serves on --port
    llamaVersion = "turboquant-fca3093";
    # CRITICAL (2026-08-13): pin CUDA archs to fleet hardware ONLY (sm_86:
    # zephyr 3090/3060 Ti + nexus 3060 Ti; sm_89: forge 4060s). nixpkgs
    # cudaPackages default builds ALL supported archs (75..121a, 9 archs);
    # TheTom's larger kernel set made the 9-arch libggml-cuda.so exceed the
    # 32-bit PLT limit at link -> "relocation truncated to fit: R_X86_64_PC32"
    # (verified failure). 2 archs fix the overflow AND cut compile ~4x.
    cudaPackages = pkgs.cudaPackages.overrideScope (final: prev: {
      flags = prev.flags // {
        cudaCapabilities = ["8.6" "8.9"];
      };
    });
  };
in
base.overrideAttrs (old: {
  # Reranker classifier head (LLM_TENSOR_CLS/CLS_OUT in
  # llama_model_llama::load_arch_tensors). The generic llama_model::build_graph
  # -> build_pooling(LLAMA_POOLING_TYPE_RANK) applies the head; without these
  # tensors RANK pooling returns empty. Needed for llama-nemotron-rerank-1b-v2.
  # Applied at build time instead of eval-time applyPatches to avoid the IFD
  # (see the forkSource comment above).
  patches = (old.patches or []) ++ [ ../patches/rerank-llama-embed.patch ];
  cmakeFlags = (old.cmakeFlags or []) ++ [
    (lib.cmakeFeature "CMAKE_C_FLAGS" "-march=x86-64-v3")
    (lib.cmakeFeature "CMAKE_CXX_FLAGS" "-march=x86-64-v3")
  ];
})
