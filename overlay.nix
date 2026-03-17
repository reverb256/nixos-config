# Custom Package Overlay
_: prev: {
  lolminer = prev.callPackage ./packages/lolminer.nix {};
  xmrig = prev.callPackage ./packages/xmrig.nix {};
  # LM Studio - both names point to the same custom package
  lmstudio = prev.callPackage ./packages/lmstudio.nix {};
  lm-studio = prev.callPackage ./packages/lmstudio.nix {};
  # WiVRn with Lighthouse support for Tundra trackers
  wivrn = prev.wivrn.overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ ["-DWIVRN_FEATURE_STEAMVR_LIGHTHOUSE=ON"];
  });
  # assimp: Disable doCheck (tests have FMA-induced floating point differences)
  # See: https://github.com/assimp/assimp/issues/5687
  assimp = prev.assimp.overrideAttrs (old: {
    doCheck = false;
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
    };
  };
}
