{
  lib,
  autoAddDriverRunpath,
  cmake,
  fetchFromGitHub,
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
    pname = "llama-cpp-ik";
    version = "eb570eb966"; # 2026-05-11, latest HEAD

    src = fetchFromGitHub {
      owner = "ikawrakow";
      repo = "ik_llama.cpp";
      rev = "eb570eb96689c235933b813693ca28ab9d3d26de";
      hash = "sha256-A9ijXABvFnSUtmLL0QqF7wgVg16ZQWGhexJL9joceDo="; # placeholder
    };

    nativeBuildInputs = with cudaPackages; [
      cmake
      git
      cuda_nvcc
      ninja
      autoAddDriverRunpath
    ];

    buildInputs = with cudaPackages; [
      cuda_cudart
      libcublas
    ];

    CFLAGS = "-march=x86-64-v3 -mtune=znver3";

    cmakeFlags = [
      (cmakeBool "GGML_CUDA" true)
      (cmakeBool "GGML_CUDA_F16" true)
      (cmakeBool "GGML_NATIVE" false)
      (cmakeBool "GGML_AVX2" true)
      (cmakeBool "GGML_FMA" true)
      (cmakeBool "GGML_F16C" true)
      (cmakeBool "GGML_AVX512" false)
      (cmakeBool "GGML_CUDA_FA" true)
      (cmakeBool "GGML_CUDA_FA_ALL_QUANTS" true)
      (cmakeBool "BUILD_SHARED_LIBS" false)
      (cmakeFeature "CMAKE_CUDA_ARCHITECTURES" "86;89")
      (cmakeFeature "CMAKE_BUILD_TYPE" "Release")
      (cmakeBool "GGML_CUDA_STATIC" true)
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      install -Dm755 bin/llama-server $out/bin/llama-server
      install -Dm755 bin/llama-cli $out/bin/llama-cli
      install -Dm755 bin/llama-perplexity $out/bin/llama-perplexity
      ln -sf llama-cli $out/bin/llama
      runHook postInstall
    '';

    meta = {
      description = "ik_llama.cpp fork with additional SOTA quants and improved hybrid GPU/CPU performance";
      homepage = "https://github.com/ikawrakow/ik_llama.cpp";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }
