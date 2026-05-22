# Vulkan backend wrapper for consolidated llama-cpp package
{ lib, llama-cpp, vulkan-headers, vulkan-loader, shaderc, glslang }:

llama-cpp {
  vulkanSupport = true;
  version = "b9048";
  sharedLibs = true;
  buildExamples = false;
  buildTests = false;
}
