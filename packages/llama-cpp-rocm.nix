# llama.cpp with ROCm support
# Built from nixpkgs with AMD GPU acceleration enabled
{
  lib,
  fetchurl,
  rocmPackages,
  cmake,
  ninja,
  git,
  stdenv,
}:

stdenv.mkDerivation rec {
  pname = "llama-cpp-rocm";
  version = "0-unstable-2025-03-19";

  src = fetchurl {
    url = "https://github.com/ggerganov/llama.cpp/archive/b739738dadf0b66a59546d7240c554d61c07c2f0.tar.gz";
    hash = "sha256-NvbsxrRpb5wCYpZ9sXOFm8QPr21LqJlnn1DQ9tg2CRM=";
  };

  nativeBuildInputs = [
    cmake
    git
    ninja
    rocmPackages.rocmcmake
    rocmPackages.pythonPackagesROCM.lld
  ];

  buildInputs = with rocmPackages; [
    clr
    clr.icd
    rocblas
    hipblas
    hipsparse
    rocfft
    rocrand
  ];

  cmakeFlags = [
    "-DGGML_HIPBLAS=ON"
    "-DGGML_HIP_UMA=OFF"
    "-DCMAKE_BUILD_TYPE=Release"
  ];

  postInstall = ''
    # Install binaries
    install -Dm755 bin/llama-server $out/bin/llama-server
    install -Dm755 bin/llama-cli $out/bin/llama-cli
    install -Dm755 bin/llama-perplexity $out/bin/llama-perplexity

    # Install all GGML libraries (including ROCm backend if built)
    find . -name "*.so*" -type f -exec install -Dm644 {} $out/lib/ \; || true

    # Create symlink for backward compatibility
    ln -sf $out/bin/llama-cli $out/bin/llama
  '';

  meta = {
    description = "Inference of Meta's LLaMA model (and others) in pure C/C++ with ROCm support";
    homepage = "https://github.com/ggerganov/llama.cpp";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
