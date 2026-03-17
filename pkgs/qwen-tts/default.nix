# Qwen3-TTS Python Package
# Official Qwen3-TTS library from PyPI
{
  lib,
  buildPythonPackage,
  fetchPypi,
  python,
  # Runtime dependencies (from pyproject.toml)
  transformers,
  accelerate,
  gradio,
  librosa,
  torchaudio,
  soundfile,
  sox,
  onnxruntime,
  einops,
  # Transitive dependencies needed
  torch,
  numpy,
  ffmpeg,
}:

buildPythonPackage rec {
  pname = "qwen-tts";
  version = "0.1.1";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-11a290d8dabc7ef91a90c54478c8ab19b3edb1d85c0882313721892bdc4af15d";
    distname = "qwen_tts";
  };

  dependencies = [
    transformers
    accelerate
    gradio
    librosa
    torchaudio
    soundfile
    sox
    onnxruntime
    einops
  ];

  # librosa needs ffmpeg
  propagatedBuildInputs = [ ffmpeg ];

  pythonImportsCheck = [ "qwen_tts" ];

  meta = {
    description = "Official Qwen3-TTS Python package for text-to-speech with voice cloning, voice design, and custom voice generation";
    homepage = "https://github.com/QwenLM/Qwen3-TTS";
    license = lib.licenses.asl20;
    maintainers = [ ];
  };
}
