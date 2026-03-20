# llama.cpp with CUDA support
# Built from latest GitHub master with GPU acceleration enabled
{
  lib,
  autoAddDriverRunpath,
  cmake,
  fetchurl,
  cudaPackages,
  git,
  ninja,
  # Accept but ignore extra parameters that nixpkgs llama-cpp might expect
  cudaSupport ? true,
  rocmSupport ? false,
  vulkanSupport ? false,
  ...
}:

let
  # Use CUDA-specific stdenv for compatibility
  effectiveStdenv = cudaPackages.backendStdenv;
  cmakeBool = option: value: "-D${option}=" + (if value then "ON" else "OFF");
  cmakeFeature = feature: value: "-D${feature}=${value}";
in
effectiveStdenv.mkDerivation rec {
  pname = "llama-cpp";
  version = "0-unstable-2025-03-19";

  src = fetchurl {
    url = "https://github.com/ggerganov/llama.cpp/archive/b739738dadf0b66a59546d7240c554d61c07c2f0.tar.gz";
    hash = "sha256-NvbsxrRpb5wCYpZ9sXOFm8QPr21LqJlnn1DQ9tg2CRM=";
  };

  nativeBuildInputs = with cudaPackages; [
    cmake
    git
    cuda_nvcc
    ninja
    autoAddDriverRunpath  # CRITICAL: Makes CUDA libraries findable at runtime
  ];

  buildInputs = with cudaPackages; [
    cuda_cccl    # CUDA C++ Core Libraries - REQUIRED for GGML_CUDA
    cuda_cudart  # CUDA Runtime
    libcublas    # CUDA BLAS library
  ];

  cmakeFlags = [
    (cmakeBool "GGML_CUDA" true)
    (cmakeBool "GGML_CUDA_F16" true)
    (cmakeBool "GGML_NATIVE" false)  # Don't use -march=native (non-deterministic)
    (cmakeBool "BUILD_SHARED_LIBS" true)
    # Only build for GPUs we have: sm_86 (RTX 3060 Ti), sm_89 (RTX 4090)
    # Much faster than building for all 7 architectures
    (cmakeFeature "CMAKE_CUDA_ARCHITECTURES" "86;89")
    (cmakeFeature "CMAKE_BUILD_TYPE" "Release")
    # Prevent CMake from adding /build/ to RPATH
    (cmakeBool "CMAKE_BUILD_RPATH_USE_ORIGIN" true)
    (cmakeBool "CMAKE_INSTALL_RPATH_USE_LINK_PATH" false)
  ];

  postInstall = ''
    # Install binaries (CMake puts them in bin/ subdirectory)
    install -Dm755 bin/llama-server $out/bin/llama-server
    install -Dm755 bin/llama-cli $out/bin/llama-cli
    install -Dm755 bin/llama-perplexity $out/bin/llama-perplexity

    # Install all GGML libraries (including CUDA backend if built)
    find . -name "*.so*" -type f -exec install -Dm644 {} $out/lib/ \; || true

    # Create symlink for backward compatibility
    ln -sf $out/bin/llama-cli $out/bin/llama
  '';

  # Fix RPATH to remove /build/ references that Nix forbids
  postFixup = ''
    find $out/bin -type f -exec patchelf --shrink-rpath {} \; || true
    find $out/lib -type f -name "*.so*" -exec patchelf --shrink-rpath {} \; || true
  '';

  meta = {
    description = "Inference of Meta's LLaMA model (and others) in pure C/C++ with CUDA support";
    homepage = "https://github.com/ggerganov/llama.cpp";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    badPlatforms = [ ]; # Works on x86_64-linux with NVIDIA GPUs
  };
}
