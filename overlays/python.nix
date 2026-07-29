{ inputs, _final, prev }:
let
  pySelf = prev.python3.pkgs;
  pySuper = pySelf;
in
{
  python3 = prev.python3.override {
    packageOverrides = py-self: py-super: {
      qwen-tts = py-self.buildPythonPackage rec {
        pname = "qwen-tts";
        version = "0.1.1";
        pyproject = true;
        src = prev.fetchurl {
          url = "https://files.pythonhosted.org/packages/39/5d/b339c4f34f22ce838d39d1c015bbad103cd4003f6826ac3afaf1553973a0/qwen_tts-0.1.1.tar.gz";
          hash = "sha256-r7pfojWAamiD9Go4nmdUC0b4pV2kVyFr8dc0KQOBR4A=";
        };
        dependencies = with py-super; [
          transformers accelerate py-self.gradio librosa torchaudio soundfile
          onnxruntime einops torch numpy
        ];
        postPatch = ''
          sed -i '/sox/d' pyproject.toml setup.cfg setup.py 2>/dev/null || true
        '';
        pythonRelaxDeps = true;
        doCheck = false;
        meta = {
          description = "Official Qwen3-TTS Python package for text-to-speech with voice cloning, voice design, and custom voice generation";
          homepage = "https://github.com/QwenLM/Qwen3-TTS";
          license = prev.lib.licenses.asl20;
        };
      };
      faster-whisper = py-self.buildPythonPackage rec {
        pname = "faster-whisper";
        version = "1.2.1";
        format = "setuptools";
        src = prev.fetchurl {
          url = "https://github.com/SYSTRAN/faster-whisper/archive/refs/tags/v1.2.1.tar.gz";
          hash = "sha256-/wtUKLOgdM1j9YCuc/oh99n9O7oo4OLgl4aNeNWwby8=";
        };
        propagatedBuildInputs = with py-super; [
          click ctranslate2 ffmpeg-python huggingface-hub numpy onnxruntime tokenizers torch
        ];
        pythonRelaxDeps = true;
        pythonRemoveDepsCheckHook = true;
        doCheck = false;
        meta = {
          description = "Faster Whisper transcription with CTranslate2";
          homepage = "https://github.com/SYSTRAN/faster-whisper";
          license = prev.lib.licenses.mit;
        };
      };
      edge-tts = py-self.buildPythonPackage rec {
        pname = "edge-tts";
        version = "7.2.7";
        format = "setuptools";
        src = prev.fetchurl {
          url = "https://github.com/rany2/edge-tts/archive/refs/tags/7.2.7.tar.gz";
          hash = "sha256-+3zBThmKlgiDEwAokCJVxdsjrQ0LfNux0Kojwe2jokw=";
        };
        propagatedBuildInputs = with py-super; [ aiohttp certifi click ];
        pythonRelaxDeps = true;
        pythonRemoveDepsCheckHook = true;
        doCheck = false;
        meta = {
          description = "Use Microsoft Edge's online text-to-speech service from Python code or by using the provided edge-tts command";
          homepage = "https://github.com/rany2/edge-tts";
          license = prev.lib.licenses.mit;
        };
      };
      pipx = py-super.pipx.overridePythonAttrs { doCheck = false; };
      gradio = py-super.gradio.overrideAttrs (old: {
        doCheck = false;
        checkPhase = false;
        dontCheckRuntimeDeps = true;
        postPatch = (old.postPatch or "") + ''
          sed -i 's/starlette<1.0/starlette<2.0/' setup.cfg pyproject.toml setup.py 2>/dev/null || true
        '';
        pythonImportsCheck = [];
      });
    };
  };
  gradio = prev.gradio.overrideAttrs (old: {
    doCheck = false;
    checkPhase = false;
    dontCheckRuntimeDeps = true;
    postPatch = (old.postPatch or "") + ''
      sed -i 's/starlette<1.0/starlette<2.0/' setup.cfg pyproject.toml setup.py 2>/dev/null || true
    '';
    pythonImportsCheck = [];
  });
}
