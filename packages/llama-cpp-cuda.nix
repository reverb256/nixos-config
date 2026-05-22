# CUDA backend wrapper for consolidated llama-cpp package
{ lib, llama-cpp, cudaPackages }:

llama-cpp {
  cudaSupport = true;
  inherit cudaPackages;
  version = "b9048";
  cudaArchitectures = "86;89";
  sharedLibs = false;
}
