{
  lib,
  autoAddDriverRunpath,
  cmake,
  cudaPackages,
  fetchFromGitHub,
  git,
  ninja,
  ...
}:

let
  effectiveStdenv = cudaPackages.backendStdenv;
  cmakeBool = option: value: "-D${option}=" + (if value then "ON" else "OFF");
in
effectiveStdenv.mkDerivation rec {
  pname = "llama-cpp-dflash";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "Luce-Org";
    repo = "lucebox-hub";
    rev = "[REDACTED:API_KEY]";
    fetchSubmodules = true;
    hash = "sha256-[REDACTED:API_KEY]+ZlLi69dw=";
  };

  sourceRoot = "source/dflash";

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
    (cmakeBool "GGML_NATIVE" false)
    "-DCMAKE_CUDA_ARCHITECTURES=86"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DGGML_CCACHE=OFF"
    "-DGGML_BUILD_TESTS=OFF"
    "-DGGML_BUILD_EXAMPLES=OFF"
  ];

  buildTargets = [ "test_dflash" ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp test_dflash $out/bin/
    runHook postInstall
  '';

  postFixup = ''
    find $out/bin -type f -exec patchelf --shrink-rpath {} \; || true
  '';

  meta = {
    description = "Lucebox DFlash speculative decoding binary for RTX 3090";
    homepage = "https://github.com/Luce-Org/lucebox-hub";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
