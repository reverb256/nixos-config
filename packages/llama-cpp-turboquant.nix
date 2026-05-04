{
  lib,
  autoAddDriverRunpath,
  cmake,
  fetchFromGitHub,
  cudaPackages,
  git,
  ninja,
  ...
}:
let
  effectiveStdenv = cudaPackages.backendStdenv;
  cmakeBool = option: value: "-D${option}=" + (if value then "ON" else "OFF");
  cmakeFeature = feature: value: "-D${feature}=${value}";
in
effectiveStdenv.mkDerivation rec {
  pname = "llama-cpp-turboquant";
  version = "0.0.3-spiritbuun-aecbbd5da";

  src = fetchFromGitHub {
    owner = "spiritbuun";
    repo = "buun-llama-cpp";
    rev = "aecbbd5daa47abd4229fb2c0906e8f102d814022";
    hash = "sha256-hXWS2R5GuRPTgmci4OxLkBNbmEHH84TmOhdeVYEnocM=";
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
    (cmakeFeature "CMAKE_CUDA_ARCHITECTURES" "86")
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
    description = "llama.cpp with DFlash speculative decoding + TurboQuant TCQ KV cache (spiritbuun fork, triattention pending rebase)";
    homepage = "https://github.com/spiritbuun/buun-llama-cpp";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
