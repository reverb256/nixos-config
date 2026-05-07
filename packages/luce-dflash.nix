{
  lib,
  autoAddDriverRunpath,
  cmake,
  fetchFromGitHub,
  cudaPackages,
  git,
  ninja,
  patchelf,
  stdenv,
  ...
}:
let
  effectiveStdenv = cudaPackages.backendStdenv;
in
effectiveStdenv.mkDerivation rec {
  pname = "luce-dflash";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "Luce-Org";
    repo = "lucebox-hub";
    rev = "fd693c72d36b7a5fd0d9a889f2798dc1c3cf379c";
    hash = "sha256-EtqPXx6QqQz7r0PS3JNzSDZuyV316nyc2A+s3Dw6UOQ=";
    fetchSubmodules = true;
  };

  sourceRoot = "source/dflash";

  nativeBuildInputs = with cudaPackages; [
    cmake
    git
    cuda_nvcc
    ninja
    autoAddDriverRunpath
    patchelf
  ];

  buildInputs = with cudaPackages; [
    cuda_cccl
    cuda_cudart
    libcublas
  ] ++ [
    stdenv.cc.cc.lib
    stdenv.cc
  ];

  cmakeBuildDir = "build";

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_CUDA_ARCHITECTURES=86"
    "-DDFLASH27B_FA_ALL_QUANTS=ON"
    "-DCMAKE_INSTALL_RPATH=$ORIGIN/../lib"
    "-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON"
  ];

  buildTargets = [ "test_dflash" ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib

    cp test_dflash $out/bin/
    find . -name "*.so*" -exec cp -L {} $out/lib/ \;

    # Fix RPATH: override build-tree paths with our lib dir
    patchelf --set-rpath "/run/opengl-driver/lib:$ORIGIN/../lib:${lib.makeLibraryPath buildInputs}" $out/bin/test_dflash

    runHook postInstall
  '';

  meta = with lib; {
    description = "Luce DFlash speculative decoding engine for Qwen3.x-27B on consumer GPUs";
    homepage = "https://github.com/Luce-Org/lucebox-hub";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
