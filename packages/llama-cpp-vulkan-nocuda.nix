# Vulkan-only llama-cpp (no CUDA) for AMD GPUs
{ lib, llama-cpp, vulkan-headers, vulkan-loader, shaderc, glslang }:
((llama-cpp.override { cudaSupport = false; }).overrideAttrs (old: {
  cmakeFlags = (old.cmakeFlags or []) ++ ["-DGGML_VULKAN=ON" "-DGGML_CUDA=OFF"];
  buildInputs = (old.buildInputs or []) ++ [vulkan-headers vulkan-loader shaderc glslang];
}))
