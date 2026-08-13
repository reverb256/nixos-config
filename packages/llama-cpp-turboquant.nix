# llama-cpp-turboquant — unified fleet binary (PrismML Bonsai + TurboQuant KV)
#
# Consumes retroheim/prism-ml-llama.cpp (pinned flake input
# llama-cpp-turboquant at rev 176bc4fda "Remove TriAttention entirely").
# That fork = ggml-org/llama.cpp base + PrismML weights (Bonsai Q1_0/Q2_0) +
# TheTom TurboQuant KV (turbo2/3/4 + TQ3_1S/TQ4_1S weight quants). Per TheTom's
# docs, turbo cache types "become available automatically once the matching
# backend is compiled in" — no extra cmake flag needed.
#
# We build ONE binary with BOTH CUDA and Vulkan backends:
#   - CUDA:  zephyr 3090/3060 Ti, nexus 3060 Ti, forge 4060s (sm_86, sm_89)
#   - Vulkan: sentry AMD RX 5600 XT (Navi 10) — llama.cpp dispatches per-device
# The derivation delegates to the fork's own .devops/nix/package.nix (standard
# llama.cpp recipe with useCuda/useVulkan toggles) via callPackage — we do NOT
# duplicate the build recipe.
#
# Why not nixpkgs llama-cpp: mainline lacks the Bonsai specializations
# (Q1_0/Q2_0 AVX512-VNNI CPU repack, CUDA __byte_perm extraction, DSpark
# drafter, --cpu-moe) and a mainline CUDA+Vulkan build stalled loading
# Bonsai-27B-Q1_0. The retroheim fork preserves Q1_0/Q2_0 ABI compatibility
# while adding TurboQuant KV compression (the 8 GB 3060 Ti / 4060s need it
# for 256k context without spilling to system RAM).
#
# PATCH (2026-08-13, verified applies clean): the fork registers per-type
# flash-attn pipelines for NV cooperative matrix v2 (FA_COOPMAT2) but its
# shader-gen never emits the per-type coopmat2 SPIR-V variants — only a
# generic flash_attn_cm2.comp + mul_mm_cm2 (matmul). Every
# CREATE_FA(..., FA_COOPMAT2, _cm2) references nonexistent symbols, so a
# CUDA+Vulkan build fails (verified twice: turbo3_0 first, then iq4_nl).
# Upstream TheTom agrees ("cm2 NV-coopmat skipped, fp32-only for turbo3",
# a09bafe). No fleet hardware uses NV coopmat2 on Vulkan (NVIDIA = CUDA,
# Navi 10 = no coopmat2), so we drop the whole flash-attn coopmat2 block.
{
  lib,
  pkgs,
  llama-cpp-turboquant,
  useCuda ? true,
  ...
}:
let
  forkSource = llama-cpp-turboquant;
  packageNix = "${forkSource}/.devops/nix/package.nix";
in
(pkgs.callPackage packageNix {
  inherit useCuda;
  useVulkan = true;
  useBlas = false;
  useMpi = false;
  useRocm = false;
  useRpc = false;
  useWebUi = false; # headless cluster; skip tools/ui npm build
  llamaVersion = "turboquant-176bc4f";
}).overrideAttrs (old: {
  patches = (old.patches or []) ++ [ ../patches/drop-fa-coopmat2.patch ];
})
