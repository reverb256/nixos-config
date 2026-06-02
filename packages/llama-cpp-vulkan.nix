# Vulkan backend wrapper for consolidated llama-cpp package
{
  lib,
  llama-cpp,
  vulkan-headers,
  vulkan-loader,
  shaderc,
  glslang,
}: (llama-cpp.overrideAttrs (old: {
  cmakeFlags = (old.cmakeFlags or []) ++ ["-DGGML_VULKAN=ON"];
  buildInputs = (old.buildInputs or []) ++ [vulkan-headers vulkan-loader shaderc glslang];
}))
