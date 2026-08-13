# llama overlay — expose the fleet's llama.cpp + llama-swap as pkgs.*
#
# packages.llama-cpp-unified (retroheim turboquant: PrismML Bonsai + TurboQuant
# KV + CUDA + Vulkan) and packages.llama-swap (mostlygeek v240) are flake
# package outputs AND must resolve inside host configs where modules reference
# `pkgs.llama-cpp-unified` / `pkgs.llama-swap`. Overlay reuses the same
# callPackage recipes so host `pkgs` and flake `packages.*` are ONE derivation.
{
  inputs,
  _final,
  prev,
}: let
  unified = prev.callPackage ../packages/llama-cpp-turboquant.nix {
    inherit (inputs) llama-cpp-turboquant;
  };
  swap = prev.callPackage ../packages/llama-swap.nix { };
in {
  llama-cpp-unified = unified;
  llama-swap = swap;
}
