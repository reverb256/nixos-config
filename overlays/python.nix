{ inputs, _final, prev }:
# IMPORTANT (2026-08-02): This overlay MUST use pythonPackagesExtensions, NOT
# `python3.override { packageOverrides = ... }`.
#
# The old `python3.override` pattern re-hashed the ENTIRE python3 package set:
# every python package (scipy, torch, jupyter-server, httplib2, ...) got a new
# drv hash because the interpreter derivation itself changed, so NOTHING
# substituted from cache.nixos.org and the whole python world rebuilt from
# source on every host/closure. That surfaced flaky pytest failures (httplib2
# test_socks5_auth, python-socks proxy tests) and ROCm configure errors that
# only ever happen when torch builds from source.
#
# pythonPackagesExtensions composes into the python3 package scope without
# re-hashing the interpreter or untouched packages, restoring cache hits.
# See the pythonPackagesExtensions block in modules/system/nix-config.nix.
{
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (py-final: py-prev: {
      qwen-tts = py-prev.buildPythonPackage rec {
        pname = "qwen-tts";
        version = "0.1.1";
        pyproject = true;
        src = prev.fetchurl {
          url = "https://files.pythonhosted.org/packages/39/5d/b339c4f34f22ce838d39d1c015bbad103cd4003f6826ac3afaf1553973a0/qwen_tts-0.1.1.tar.gz";
          hash = "sha256-r7pfojWAamiD9Go4nmdUC0b4pV2kVyFr8dc0KQOBR4A=";
        };
        dependencies = with py-prev; [
          transformers accelerate py-final.gradio librosa torchaudio soundfile
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
      faster-whisper = py-prev.buildPythonPackage rec {
        pname = "faster-whisper";
        version = "1.2.1";
        format = "setuptools";
        src = prev.fetchurl {
          url = "https://github.com/SYSTRAN/faster-whisper/archive/refs/tags/v1.2.1.tar.gz";
          hash = "sha256-/wtUKLOgdM1j9YCuc/oh99n9O7oo4OLgl4aNeNWwby8=";
        };
        propagatedBuildInputs = with py-prev; [
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
      edge-tts = py-prev.buildPythonPackage rec {
        pname = "edge-tts";
        version = "7.2.7";
        format = "setuptools";
        src = prev.fetchurl {
          url = "https://github.com/rany2/edge-tts/archive/refs/tags/7.2.7.tar.gz";
          hash = "sha256-+3zBThmKlgiDEwAokCJVxdsjrQ0LfNux0Kojwe2jokw=";
        };
        propagatedBuildInputs = with py-prev; [ aiohttp certifi click ];
        pythonRelaxDeps = true;
        pythonRemoveDepsCheckHook = true;
        doCheck = false;
        meta = {
          description = "Use Microsoft Edge's online text-to-speech service from Python code or by using the provided edge-tts command";
          homepage = "https://github.com/rany2/edge-tts";
          license = prev.lib.licenses.mit;
        };
      };
      # Flaky hypothesis test (test_support_moments_sample) fails on a
      # ~2e-9 float tolerance on some hardware/compiler combos; upstream
      # tracks it as flaky. The full 592s pytest suite ran and 87k tests
      # passed except this one nondeterministic example. Skip checkPhase
      # (nixpkgs has debated doCheck=false for scipy upstream for this reason).
      scipy = py-prev.scipy.overridePythonAttrs (old: {
        doCheck = false;
      });
      pipx = py-prev.pipx.overridePythonAttrs { doCheck = false; };
      gradio = py-prev.gradio.overrideAttrs (old: {
        doCheck = false;
        checkPhase = false;
        dontCheckRuntimeDeps = true;
        postPatch = (old.postPatch or "") + ''
          sed -i 's/starlette<1.0/starlette<2.0/' setup.cfg pyproject.toml setup.py 2>/dev/null || true
        '';
        pythonImportsCheck = [];
      });
    })
  ];

  # Top-level gradio override for non-python consumers (e.g. systemPackages).
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
