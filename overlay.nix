{ inputs }:
_final: prev:
{
  inherit (inputs.compute-market.packages.x86_64-linux)
    lolminer
    xmrig
    ;
  lmstudio = prev.callPackage ./packages/lmstudio.nix { };
  srbminer-multi = prev.callPackage ./packages/srbminer.nix { };
  lpminer-pearl = prev.callPackage ./packages/lpminer.nix { };
  peakminer = prev.callPackage ./pkgs/peakminer.nix { };
  # DBD-CSV 0.60 test failures in sandbox (Using data files in /build... is unsafe)
  perlPackages = prev.perlPackages // {
    DBDCSV = prev.perlPackages.DBDCSV.overrideAttrs (old: {
      doCheck = false;
    });
  };
  haven-desktop = prev.callPackage ./packages/haven-desktop.nix { };
  kokoro-tts = prev.callPackage ./packages/kokoro-tts.nix { };
  chatterbox-tts = prev.callPackage ./packages/chatterbox-tts.nix { };
  wivrn = prev.wivrn.overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ [ "-DWIVRN_FEATURE_STEAMVR_LIGHTHOUSE=ON" ];
  });
  # assimp tests fail on musl; disable globally since nothing in this config needs them
  assimp = prev.assimp.overrideAttrs (_old: {
    doCheck = false;
  });
  # gradio tests fail due to missing matplotlib and starlette version check; disable globally
  gradio = prev.gradio.overrideAttrs (old: {
    doCheck = false;
    checkPhase = false;
    dontCheckRuntimeDeps = true;
    postPatch = (old.postPatch or "") + ''
      sed -i 's/starlette<1.0/starlette<2.0/' setup.cfg pyproject.toml setup.py 2>/dev/null || true
    '';
    pythonImportsCheck = [ ];
  });
  llama-cpp = prev.callPackage ./packages/llama-cpp.nix {
    cudaSupport = true;
    inherit (prev) cudaPackages;
  };
  llama-cpp-ik = prev.callPackage ./packages/llama-cpp-ik.nix { };
  llama-cpp-rocm = prev.callPackage ./packages/llama-cpp-rocm.nix { };
  llama-cpp-vulkan = prev.callPackage ./packages/llama-cpp-vulkan.nix { };
  llama-cpp-vulkan-nocuda = prev.callPackage ./packages/llama-cpp-vulkan-nocuda.nix { };
  # TODO: broken placeholder rev/hash — re-enable when source is valid
  # llama-cpp-dflash = prev.callPackage ./packages/llama-cpp-dflash.nix {};
  # dflash-server = prev.callPackage ./packages/dflash-server.nix {};
  ai-inference-gateway = inputs.ai-gateway.packages.x86_64-linux.default;
  inherit (inputs.caddy-ingress.packages.x86_64-linux)
    caddy-with-modules
    ;
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
          click
          ctranslate2
          ffmpeg-python
          huggingface-hub
          numpy
          onnxruntime
          tokenizers
          torch
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
        propagatedBuildInputs = with py-super; [
          aiohttp
          certifi
          click
        ];
        pythonRelaxDeps = true;
        pythonRemoveDepsCheckHook = true;
        doCheck = false;
        meta = {
          description = "Use Microsoft Edge's online text-to-speech service from Python code or using the provided edge-tts command";
          homepage = "https://github.com/rany2/edge-tts";
          license = prev.lib.licenses.mit;
        };
      };
      # Fix: pipx 1.8.0 test failures (spaces around @)
      pipx = py-super.pipx.overridePythonAttrs { doCheck = false; };
      gradio = py-super.gradio.overrideAttrs (old: {
        doCheck = false;
        checkPhase = false;
        dontCheckRuntimeDeps = true;
        # gradio <1.0 requires starlette<1.0 but nixpkgs ships starlette 1.1.0
        postPatch = (old.postPatch or "") + ''
          sed -i 's/starlette<1.0/starlette<2.0/' setup.cfg pyproject.toml setup.py 2>/dev/null || true
        '';
        pythonImportsCheck = [ ];
      });
    };
  };

  # Fix firefoxpwa - create missing lib/firefoxpwa directory
  firefoxpwa-unwrapped = prev.firefoxpwa-unwrapped.overrideAttrs (old: {
    postInstall = old.postInstall + ''
      # Create empty `lib/firefoxpwa` directory so the Firefox wrapper won\x27t fail
      # trying to disable the update checks. It will try to write to
      # `$out/lib/firefoxpwa/is-packaged-app`, which doesn\x27t exist by default.
      mkdir -p $out/lib/firefoxpwa
    '';
  });

  claude-code-image = prev.callPackage ./packages/claude-code-image.nix { };
  opencode-image = prev.callPackage ./packages/opencode-image.nix { };
  # maplespike images are built locally in nixos-config/packages/maplespike-*.nix
  # (maplespike repo is self-contained source; nixos-config is the OS)
  hermes-chat = prev.callPackage ./packages/hermes-chat.nix { };
  # hermes-workspace and hermes-webui archived (2026-05-16)
  privacy-filter = prev.callPackage ./packages/privacy-filter.nix {
    transformers-dev = prev.callPackage ./packages/transformers-dev.nix { };
  };
  # dufs tests require CA certificates for reqwest-based HTTP client
  # Provide cacert and set SSL_CERT_FILE during test phase
  dufs = prev.dufs.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ prev.cacert ];
    env = (old.env or {}) // {
      SSL_CERT_FILE = "${prev.cacert}/etc/ssl/certs/ca-bundle.crt";
      REQUESTS_CA_BUNDLE = "${prev.cacert}/etc/ssl/certs/ca-bundle.crt";
    };
  });

} // prev.lib.optionalAttrs (inputs ? vllm) {
  vllm-turboquant-env = inputs.vllm.packages.x86_64-linux.vllm-turboquant-env;
} // prev.lib.optionalAttrs (inputs ? llama-turboquant) {
  llama-cpp-turboquant = inputs.llama-turboquant.packages.x86_64-linux.llama-cpp-turboquant.overrideAttrs (old: {
    src = prev.fetchFromGitHub {
      owner = "AmesianX";
      repo = "TurboQuant";
      rev = "v${old.version}";
      hash = "sha256-Jxje/SMyI7l1YJQXcwFBu8CPzxpZb5VPZ+gmEWGoZUA=";
    };
  });
}
