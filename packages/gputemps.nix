{
  lib,
  stdenv,
  fetchFromGitHub,
  gnumake,
  gcc,
  pciutils,
  cudaPackages,
}:
let
  nvmlInclude = cudaPackages.cuda_nvml_dev.include;
  nvmlStubs = cudaPackages.cuda_nvml_dev.stubs;
in
stdenv.mkDerivation rec {
  pname = "gputemps";
  version = "0.1.0-unstable-2026-07-19";

  src = fetchFromGitHub {
    owner = "ThomasBaruzier";
    repo = "gddr6-core-junction-vram-temps";
    rev = "fefe15744ed19d7959fa7a584c86b858767c4a98";
    sha256 = "sha256-jSHbnczG8+dlZc7QZ9zGeWYoQs0hcH8nj8pa6JMymfc=";
  };

  nativeBuildInputs = [ gnumake gcc ];
  buildInputs = [ pciutils nvmlInclude nvmlStubs ];

  preConfigure = ''
    export NVML_HEADER="${nvmlInclude}/include/nvml.h"
    export NVML_CPPFLAGS="-I${nvmlInclude}/include"
  '';

  buildFlags = [
    "CC=${gcc}/bin/cc"
    "LDFLAGS=-L${nvmlStubs}/lib/stubs"
  ];

  installPhase = ''
    runHook preInstall
    install -Dm0755 gputemps $out/bin/gputemps
    runHook postInstall
  '';

  enableParallelBuilding = true;

  meta = with lib; {
    description = "Read core, junction, and VRAM temperatures for NVIDIA GDDR6/GDDR6X/GDDR7 GPUs via BAR0 MMIO (Paulo Gomes method)";
    homepage = "https://github.com/ThomasBaruzier/gddr6-core-junction-vram-temps";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "gputemps";
  };
}
