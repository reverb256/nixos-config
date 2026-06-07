{
  lib,
  stdenv,
  fetchurl,
  cmake,
  ninja,
  pkg-config,
  # Backend options
  cudaSupport ? false,
  cudaPackages ? null,
  vulkanSupport ? false,
  rocmSupport ? false,
  rocmPackages ? null,
  # Vulkan dependencies
  vulkan-headers ? null,
  vulkan-loader ? null,
  shaderc ? null,
  glslang ? null,
  # Build configuration
  version ? "b9048",
  # Feature flags
  native ? false,
  sharedLibs ? false,
  buildExamples ? true,
  buildTests ? false,
  buildServer ? true,
  openSSL ? false,
  cudaArchitectures ? "86;89",
  extraCmakeFlags ? [],
  ...
}: let
  # Default source if not provided
  defaultSrc = fetchurl {
    url = "https://github.com/ggml-org/llama.cpp/archive/refs/tags/${version}.tar.gz";
    hash = "sha256-SIu8R1TCYufGbaclhZGb2qdgBFZyY4ZFX9RlaxXYJX8=";
  };
  # src defined as let binding above

  # Determine which backend stdenv to use
  effectiveStdenv =
    if cudaSupport && cudaPackages != null
    then cudaPackages.backendStdenv
    else if rocmSupport && rocmPackages != null
    then rocmPackages.backendStdenv
    else stdenv;

  # Helper functions for cmake flags
  cmakeBool = option: value: "-D${option}=${
    if value
    then "ON"
    else "OFF"
  }";
  cmakeFeature = feature: value: "-D${feature}=${value}";

  # Base build inputs
  baseNativeBuildInputs = [cmake ninja pkg-config];
  baseBuildInputs = [];

  # CUDA-specific inputs
  cudaNativeBuildInputs = lib.optionals cudaSupport (with cudaPackages; [
    cuda_nvcc
  ]);
  cudaBuildInputs = lib.optionals cudaSupport (with cudaPackages; [
    cuda_cccl
    cuda_cudart
    libcublas
  ]);

  # Vulkan inputs
  vulkanBuildInputs = lib.optionals vulkanSupport [
    vulkan-headers
    vulkan-loader
    shaderc
    glslang
  ];

  # ROCm inputs
  rocmBuildInputs = lib.optionals rocmSupport (with rocmPackages; [
    rocm-core
    hip-runtime-amd
  ]);

  # Combine all inputs
  nativeBuildInputs = baseNativeBuildInputs ++ cudaNativeBuildInputs;
  buildInputs = baseBuildInputs ++ cudaBuildInputs ++ vulkanBuildInputs ++ rocmBuildInputs;

  # Base cmake flags
  baseCmakeFlags = [
    (cmakeBool "GGML_NATIVE" native)
    (cmakeBool "BUILD_SHARED_LIBS" sharedLibs)
    (cmakeBool "LLAMA_BUILD_EXAMPLES" buildExamples)
    (cmakeBool "LLAMA_BUILD_TESTS" buildTests)
    (cmakeBool "LLAMA_BUILD_SERVER" buildServer)
    (cmakeBool "LLAMA_OPENSSL" openSSL)
    (cmakeFeature "CMAKE_BUILD_TYPE" "Release")
  ];

  # Backend-specific cmake flags
  cudaCmakeFlags = lib.optionals cudaSupport [
    (cmakeBool "GGML_CUDA" true)
    (cmakeBool "GGML_CUDA_F16" true)
    (cmakeFeature "CMAKE_CUDA_ARCHITECTURES" cudaArchitectures)
    (cmakeBool "CMAKE_BUILD_RPATH_USE_ORIGIN" true)
    (cmakeBool "CMAKE_INSTALL_RPATH_USE_LINK_PATH" false)
  ];

  vulkanCmakeFlags = lib.optionals vulkanSupport [
    (cmakeBool "GGML_VULKAN" true)
  ];

  rocmCmakeFlags = lib.optionals rocmSupport [
    (cmakeBool "GGML_HIPBLAS" true)
    (cmakeBool "GGML_CUDA" false) # Ensure CUDA is disabled for ROCm
  ];

  # Combine all cmake flags
  cmakeFlags = baseCmakeFlags ++ cudaCmakeFlags ++ vulkanCmakeFlags ++ rocmCmakeFlags ++ extraCmakeFlags;
in
  effectiveStdenv.mkDerivation {
    pname = "llama-cpp";
    inherit version;
    src = defaultSrc;

    inherit nativeBuildInputs buildInputs cmakeFlags;

    postInstall = ''
      # Install binaries (use || true for optional ones that may not exist in all versions)
      install -Dm755 bin/llama-server $out/bin/llama-server
      install -Dm755 bin/llama-cli $out/bin/llama-cli
      install -Dm755 bin/llama-perplexity $out/bin/llama-perplexity  || true
      install -Dm755 bin/llama-quantize $out/bin/llama-quantize      || true
      install -Dm755 bin/llama-evaluate $out/bin/llama-evaluate      || true

      # Create convenience symlinks
      ln -sf llama-cli $out/bin/llama

      # Install any additional llama-* binaries that exist
      for bin in bin/llama-*; do
        if [ -f "$bin" ]; then
          install -Dm755 "$bin" "$out/bin/$(basename $bin)" || true
        fi
      done
    '';

    postFixup = lib.optionalString stdenv.isLinux ''
      # Shrink RPATH for smaller binaries
      find $out/bin -type f -executable -exec patchelf --shrink-rpath {} \; || true
    '';

    meta = {
      description =
        "Inference of Meta's LLaMA model (and others) in pure C/C++"
        + lib.optionalString cudaSupport " with CUDA support"
        + lib.optionalString vulkanSupport " with Vulkan support"
        + lib.optionalString rocmSupport " with ROCm support";
      homepage = "https://github.com/ggml-org/llama.cpp";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "llama-cli";
    };
  }
