# CUDA backend wrapper for consolidated llama-cpp package
{
  lib,
  llama-cpp,
  cudaPackages,
}: (llama-cpp.overrideAttrs (old: {
  cmakeFlags = (old.cmakeFlags or []) ++ ["-DGGML_CUDA=ON"];
  buildInputs = (old.buildInputs or []) ++ (with cudaPackages; [cuda_cudart cuda_driver]);
}))
