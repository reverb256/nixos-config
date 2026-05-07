{
  lib,
  stdenv,
  ...
}:
# DFlash - Speculative Decoding for Qwen3.6-27B Dense
#
# DFlash is for DENSE models only. MoE models (35B-A3B) cannot use it efficiently.
#
# Current: Qwen3.6-35B-A3B (MoE) → TurboQuant (no speculative decoding)
# Future: Qwen3.6-27B Dense → DFlash (3x speedup) - HF model: z-lab/Qwen3.6-27B-DFlash
#
# Implementation requires:
# 1. llama-turboquant fork with DFlash support OR upstream llama.cpp
# 2. GGUF conversion of DFlash draft model
# 3. llama-server with --dflash and -md draft flags
#
# See: https://github.com/ggml-org/llama.cpp/pull/22105
let
  buildScript = ''
        mkdir -p $out/bin
        cat > $out/bin/DFLASH_READY.md << 'EOF'
    # DFlash Speculative Decoding Setup

    ## Current Model: Qwen3.6-35B-A3B (MoE)
    - TurboQuant KV cache compression active
    - DFlash NOT compatible (MoE recurrent state limitation)

    ## Pending: Qwen3.6-27B Dense + DFlash
    Status: Draft model available on HuggingFace
    - HF: z-lab/Qwen3.6-27B-DFlash
    - Expected speedup: 3x

    To enable when model is ready:
    1. Convert HF draft to GGUF: python convert_hf_to_gguf.py z-lab/Qwen3.6-27B-DFlash --outfile draft.gguf
    2. Update llama-server deployment with:
       -m target.gguf -md draft.gguf --dflash --draft-max 16
    3. Download model: huggingface-cli download z-lab/Qwen3.6-27B-DFlash model.safetensors
    EOF
        chmod +x $out/bin/DFLASH_READY.md
  '';
in
  stdenv.mkDerivation rec {
    pname = "llama-cpp-dflash";
    version = "1.0.0";

    dontBuild = true;
    installPhase = buildScript;

    meta = {
      description = "DFlash for Qwen3.6-27B Dense - 3x speedup";
      homepage = "https://github.com/ggml-org/llama.cpp/pull/22105";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      longDescription = ''
        DFlash speculative decoding for dense Qwen models.

        Qwen3.6-27B Dense (pending):
          - HF draft model: z-lab/Qwen3.6-27B-DFlash
          - Expected 3x throughput speedup
          - See DFLASH_READY.md for setup instructions

        Qwen3.6-35B-A3B (current, MoE):
          - DFlash NOT compatible
          - Uses TurboQuant KV cache compression instead
      '';
    };
  }
