{
  lib,
  autoAddDriverRunpath,
  cmake,
  fetchurl,
  cudaPackages,
  git,
  ninja,
  ...
}: let
  effectiveStdenv = cudaPackages.backendStdenv;
  cmakeBool = option: value:
    "-D${option}="
    + (
      if value
      then "ON"
      else "OFF"
    );
  cmakeFeature = feature: value: "-D${feature}=${value}";
in
  effectiveStdenv.mkDerivation rec {
    pname = "llama-cpp";
    version = "b9048";
    src = fetchurl {
      url = "https://github.com/ggml-org/llama.cpp/archive/refs/tags/b9048.tar.gz";
      hash = "sha256-SIu8R1TCYufGbaclhZGb2qdgBFZyY4ZFX9RlaxXYJX8=";
    };
    nativeBuildInputs = with cudaPackages; [
      cmake
      git
      cuda_nvcc
      ninja
      autoAddDriverRunpath
    ];
    buildInputs = with cudaPackages; [
      cuda_cccl
      cuda_cudart
      libcublas
    ];
    cmakeFlags = [
      (cmakeBool "GGML_CUDA" true)
      (cmakeBool "GGML_CUDA_F16" true)
      (cmakeBool "GGML_NATIVE" false)
      (cmakeBool "BUILD_SHARED_LIBS" false)
      (cmakeFeature "CMAKE_CUDA_ARCHITECTURES" "86;89")
      (cmakeFeature "CMAKE_BUILD_TYPE" "Release")
      (cmakeBool "CMAKE_BUILD_RPATH_USE_ORIGIN" true)
      (cmakeBool "CMAKE_INSTALL_RPATH_USE_LINK_PATH" false)
    ];
    postInstall = ''
      install -Dm755 bin/llama-server $out/bin/llama-server
      install -Dm755 bin/llama-cli $out/bin/llama-cli
      install -Dm755 bin/llama-perplexity $out/bin/llama-perplexity
      ln -sf $out/bin/llama-cli $out/bin/llama
    '';
    postFixup = ''
      find $out/bin -type f -exec patchelf --shrink-rpath {} \; || true
    '';
    meta = {
      description = "Inference of Meta's LLaMA model (and others) in pure C/C++ with CUDA support";
      homepage = "https://github.com/ggerganov/llama.cpp";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      badPlatforms = [];
    };
  }
