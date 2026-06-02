# ROCm backend wrapper for consolidated llama-cpp package
{
  lib,
  llama-cpp,
  rocmPackages,
}: (llama-cpp.overrideAttrs (old: {
  cmakeFlags = (old.cmakeFlags or []) ++ ["-DGGML_HIPBLAS=ON" "-DGGML_CUDA=OFF"];
  buildInputs = (old.buildInputs or []) ++ (with rocmPackages; [rocm-core hip-runtime-amd]);
}))
