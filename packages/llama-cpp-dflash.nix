{
  lib,
  stdenv,
  ...
}:

# DFlash - Manual Build Required
# 
# DFlash speculative decoding for RTX 3090. Requires Luce-Org/lucebox-hub with git submodules
# (pulls pinned Luce-Org/llama.cpp@luce-dflash fork).
#
# Use for: Qwen3.6-27B Dense (when available) - NOT for MoE models like 35B-A3B
#
# Build manually:
#   git clone --recurse-submodules https://github.com/Luce-Org/lucebox-hub && cd lucebox-hub/dflash
#   cmake -B build -S . -DCMAKE_CUDA_ARCHITECTURES=86 -DCMAKE_BUILD_TYPE=Release
#   cmake --build build --target test_dflash -j
#   cp build/test_dflash $out/bin/
#
# See: https://github.com/Luce-Org/lucebox-hub#02--dflash-qwen35-27b-gguf-on-rtx-3090

let
  # Stub package - actual binary requires manual build with submodules
  buildScript = ''
    mkdir -p $out/bin
    cat > $out/bin/INSTALL_NOTICE << 'EOF'
DFlash requires manual build.
See: https://github.com/Luce-Org/lucebox-hub#02--dflash-qwen35-27b-gguf-on-rtx-3090

Build steps:
  git clone --recurse-submodules https://github.com/Luce-Org/lucebox-hub
  cd lucebox-hub/dflash
  cmake -B build -S . -DCMAKE_CUDA_ARCHITECTURES=86 -DCMAKE_BUILD_TYPE=Release
  cmake --build build --target test_dflash -j
  cp build/test_dflash /your/path/bin/
EOF
    chmod +x $out/bin/INSTALL_NOTICE
  '';
in

stdenv.mkDerivation rec {
  pname = "llama-cpp-dflash";
  version = "0.1.0-manual";

  dontBuild = true;
  installPhase = buildScript;

  meta = {
    description = "DFlash speculative decoding binary - manual build required";
    homepage = "https://github.com/Luce-Org/lucebox-hub";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    longDescription = ''
      DFlash speculative decoding for Qwen3.6-27B Dense on RTX 3090.
      Provides 3-5x speedup over autoregressive decoding.
      
      IMPORTANT: This package requires manual build due to git submodule dependencies.
      See installation instructions at: ${meta.homepage}
      
      Model compatibility: Dense models ONLY (27B). NOT for MoE models (35B-A3B).
    '';
  };
}
