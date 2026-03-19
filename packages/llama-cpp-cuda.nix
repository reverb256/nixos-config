# llama.cpp with CUDA support
# Built from latest GitHub master with GPU acceleration enabled
{
  lib,
  stdenv,
  cmake,
  fetchurl,
  cudaPackages,
  git,
}:
stdenv.mkDerivation rec {
  pname = "llama-cpp";
  version = "0-unstable-2025-03-19";

  src = fetchurl {
    url = "https://github.com/ggerganov/llama.cpp/archive/b739738dadf0b66a59546d7240c554d61c07c2f0.tar.gz";
    hash = "sha256-Aimcr7FSqSoytucprXk5aH1BKg+mk08/2iZwbVC3Fg8=";
  };

  nativeBuildInputs = [
    cmake
    git
  ];

  buildInputs = with cudaPackages; [
    cuda_nvrtc
    cuda_cudart
  ];

  cmakeFlags = [
    "-DLLAMA_CUDA=ON"
    "-DLLAMA_CUDA_F16=ON"
    "-DCMAKE_BUILD_TYPE=Release"
  ];

  postInstall = ''
    # Install binaries
    install -Dm755 llama-server $out/bin/llama-server
    install -Dm755 llama-cli $out/bin/llama-cli
    install -Dm755 llama-perplexity $out/bin/llama-perplexity

    # Install libraries
    install -Dm644 libllama.so $out/lib/libllama.so
  '';

  meta = {
    description = "Inference of Meta's LLaMA model (and others) in pure C/C++ with CUDA support";
    homepage = "https://github.com/ggerganov/llama.cpp";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    badPlatforms = [ ]; # Works on x86_64-linux with NVIDIA GPUs
  };
}
