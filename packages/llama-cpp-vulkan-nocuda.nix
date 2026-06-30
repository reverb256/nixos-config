# Pure Vulkan llama.cpp — no CUDA support for hosts where NVIDIA GPUs are busy mining
{ lib, llama-cpp, vulkan-headers, vulkan-loader, shaderc, glslang }:
(llama-cpp.override {
  cudaSupport = false;
}).overrideAttrs (old: {
  cmakeFlags = (old.cmakeFlags or []) ++ ["-DGGML_VULKAN=ON" "-DGGML_CUDA=OFF"];
  buildInputs = (old.buildInputs or []) ++ [vulkan-headers vulkan-loader shaderc glslang];
})
