# Custom Package Overlay
_: prev: {
  lolminer = prev.callPackage ./packages/lolminer.nix { };
  xmrig = prev.callPackage ./packages/xmrig.nix { };
  # LM Studio - both names point to the same custom package
  lmstudio = prev.callPackage ./packages/lmstudio.nix { };
  lm-studio = prev.callPackage ./packages/lmstudio.nix { };
  # WiVRn with Lighthouse support for Tundra trackers
  wivrn = prev.wivrn.overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ [ "-DWIVRN_FEATURE_STEAMVR_LIGHTHOUSE=ON" ];
  });
  # assimp: Disable doCheck (tests have FMA-induced floating point differences)
  # See: https://github.com/assimp/assimp/issues/5687
  assimp = prev.assimp.overrideAttrs (old: {
    doCheck = false;
  });

  # llama-cpp: Updated to b8429 (latest) for Qwen3.5 compatibility
  # The previous pin to 8244 was completely broken for Qwen3.5.
  # Latest version includes all Qwen3.5 tokenizer and template fixes.
  # Commit: 1e645345702154ba4813d3d9bbdbd97718de82c0
  llama-cpp = prev.llama-cpp.overrideAttrs (old: {
    version = "b8429";
    src = prev.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      rev = "1e645345702154ba4813d3d9bbdbd97718de82c0";
      sha256 = lib.fakeSha256;
    };
  });

  # Python packages overlay
  python3 = prev.python3.override {
    packageOverrides = py-self: py-super: {
      # qwen-tts: Official Qwen3-TTS Python package from PyPI
      # Source: https://github.com/QwenLM/Qwen3-TTS
      # PyPI: https://pypi.org/project/qwen-tts/
      # Models loaded from HuggingFace: Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice
      qwen-tts = py-self.buildPythonPackage rec {
        pname = "qwen-tts";
        version = "0.1.1";
        pyproject = true;

        src = prev.fetchurl {
          url = "https://files.pythonhosted.org/packages/39/5d/b339c4f34f22ce838d39d1c015bbad103cd4003f6826ac3afaf1553973a0/qwen_tts-0.1.1.tar.gz";
          hash = "sha256-r7pfojWAamiD9Go4nmdUC0b4pV2kVyFr8dc0KQOBR4A=";
        };

        # Dependencies from pyproject.toml
        dependencies = with py-super; [
          transformers
          accelerate
          gradio
          librosa
          torchaudio
          soundfile
          onnxruntime
          einops
          torch
          numpy
        ];

        # Patch metadata to remove sox references (optional external dep)
        postPatch = ''
          sed -i '/sox/d' pyproject.toml setup.cfg setup.py 2>/dev/null || true
        '';

        # Relax version constraints - qwen-tts pins specific versions
        pythonRelaxDeps = true;
        # Disable tests - they require downloading models
        doCheck = false;

        meta = {
          description = "Official Qwen3-TTS Python package for text-to-speech with voice cloning, voice design, and custom voice generation";
          homepage = "https://github.com/QwenLM/Qwen3-TTS";
          license = prev.lib.licenses.asl20;
        };
      };

      # faster-whisper: Faster Whisper transcription with CTranslate2
      # Source: https://github.com/SYSTRAN/faster-whisper
      # Note: No source distribution on PyPI, using GitHub release
      faster-whisper = py-self.buildPythonPackage rec {
        pname = "faster-whisper";
        version = "1.2.1";
        format = "setuptools";

        src = prev.fetchurl {
          url = "https://github.com/SYSTRAN/faster-whisper/archive/refs/tags/v1.2.1.tar.gz";
          hash = "sha256-/wtUKLOgdM1j9YCuc/oh99n9O7oo4OLgl4aNeNWwby8=";
        };

        # Core dependencies
        propagatedBuildInputs = with py-super; [
          click
          ctranslate2
          ffmpeg-python
          huggingface-hub
          numpy
          onnxruntime
          tokenizers
          torch
        ];

        # Relax version constraints - faster-whisper pins specific versions
        pythonRelaxDeps = true;
        # Disable dependency checks
        pythonRemoveDepsCheckHook = true;
        doCheck = false;

        meta = {
          description = "Faster Whisper transcription with CTranslate2";
          homepage = "https://github.com/SYSTRAN/faster-whisper";
          license = prev.lib.licenses.mit;
        };
      };

      # edge-tts: Microsoft Edge's online text-to-speech service
      # Source: https://github.com/rany2/edge-tts
      # Note: PyPI source distribution has certifi dependency issues, using GitHub release
      edge-tts = py-self.buildPythonPackage rec {
        pname = "edge-tts";
        version = "7.2.7";
        format = "setuptools";

        src = prev.fetchurl {
          url = "https://github.com/rany2/edge-tts/archive/refs/tags/7.2.7.tar.gz";
          hash = "sha256-+3zBThmKlgiDEwAokCJVxdsjrQ0LfNux0Kojwe2jokw=";
        };

        # Dependencies
        propagatedBuildInputs = with py-super; [
          aiohttp
          certifi
          click
        ];

        # Relax version constraints for certifi compatibility
        pythonRelaxDeps = true;
        # Disable dependency checks
        pythonRemoveDepsCheckHook = true;
        doCheck = false;

        meta = {
          description = "Use Microsoft Edge's online text-to-speech service from Python code or using the provided edge-tts command";
          homepage = "https://github.com/rany2/edge-tts";
          license = prev.lib.licenses.mit;
        };
      };
    };
  };
}
