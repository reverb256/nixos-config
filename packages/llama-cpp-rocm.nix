# ROCm backend wrapper for consolidated llama-cpp package
{ lib, llama-cpp, rocmPackages }:

llama-cpp {
  rocmSupport = true;
  inherit rocmPackages;
  version = "b9048";
  sharedLibs = false;
}
