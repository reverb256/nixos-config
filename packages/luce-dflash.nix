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
    ];

    buildInputs = with cudaPackages; [
      cccl
      cuda_cudart
      libcublas
    ];

    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DCMAKE_CUDA_ARCHITECTURES=86"
      "-DDFLASH27B_FA_ALL_QUANTS=ON"
      "-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF"
      "-DCMAKE_SKIP_BUILD_RPATH=ON"
    ];

    buildTargets = ["test_dflash"];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      find . -name "test_dflash" -type f -executable -exec cp {} $out/bin/ \;
      runHook postInstall
    '';

    # Fix RPATH after install
    postFixup = ''
      patchelf --set-rpath "${lib.makeLibraryPath (with cudaPackages; [cuda_cudart libcublas cccl])}" $out/bin/test_dflash
    '';

    meta = with lib; {
      description = "Luce DFlash speculative decoding engine for Qwen3.x-27B on consumer GPUs";
      homepage = "https://github.com/Luce-Org/lucebox-hub";
      license = licenses.mit;
      platforms = ["x86_64-linux"];
    };
  }
