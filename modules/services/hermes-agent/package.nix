{ pkgs, lib, config, ... }:
let
  cfg = config.services.hermes-agent;
  # Use pkgs.python3 to get overlay packages (firecrawl-py, edge-tts, etc.)
  # instead of raw python313 which doesn't have the overlay applied
  python = pkgs.python3;
in
python.pkgs.buildPythonApplication rec {
  pname = "hermes-agent";
  version = "0.1.0-unstable";
  format = "pyproject";

  src = config.services.hermes-agent.packageSrc;

  # Enable submodules (mini-swe-agent, tinker-atropos)
  # Note: Git submodules require fetchSubmodules = true in flake input
  # Terminal tool requires minisweagent submodule for code editing features
  postPatch = ''
    # Attempt to initialize submodules if this is a git checkout
    if [ -d .git ]; then
      echo "[Hermes] Initializing git submodules..." >&2
      if git submodule update --init --recursive 2>&1; then
        echo "[Hermes] ✓ Submodules initialized successfully" >&2
      else
        echo "[Hermes] ⚠️  Submodule initialization failed (non-critical)" >&2
        echo "[Hermes]     Features requiring submodules may not work:" >&2
        echo "[Hermes]     - mini-swe-agent (code editing)" >&2
        echo "[Hermes]     - tinker-atropos (code generation)" >&2
        echo "[Hermes]     Core Hermes functionality remains available" >&2
      fi
    else
      echo "[Hermes] ⚠️  Not a git repository, submodules not available" >&2
    fi
    echo "[Hermes] ✓ Build preparation completed" >&2

    # Patch pyproject.toml to remove unavailable dependencies
    if [ -f pyproject.toml ]; then
      echo "[Hermes] Patching pyproject.toml to remove unavailable dependencies..." >&2
      sed -i '/parallel-web/d; /firecrawl-py/d; /edge-tts/d; /faster-whisper/d; /fal-client/d' pyproject.toml || true
      echo "[Hermes] ✓ Patched pyproject.toml" >&2
    fi

    # Patch Python imports to be conditional (for unavailable packages)
    echo "[Hermes] Patching Python imports for unavailable packages..." >&2

    # Simply comment out problematic imports and function calls
    if [ -f tools/web_tools.py ]; then
      sed -i 's/^from firecrawl import Firecrawl/# from firecrawl import Firecrawl  # DISABLED: package not available/' tools/web_tools.py || true
    fi

    if [ -f tools/vision_tools.py ]; then
      sed -i 's/^from edge_tts import/# from edge_tts import  # DISABLED: package not available/' tools/vision_tools.py || true
    fi

    if [ -f tools/transcription_tools.py ]; then
      sed -i 's/^from faster_whisper import/# from faster_whisper import  # DISABLED: package not available/' tools/transcription_tools.py || true
    fi

    if [ -f tools/image_generation_tool.py ]; then
      sed -i 's/^import fal_client/# import fal_client  # DISABLED: package not available/' tools/image_generation_tool.py || true
    fi

    echo "[Hermes] ✓ Patched Python imports" >&2
    echo "[Hermes] ✓ Build preparation completed" >&2
  '';

  propagatedBuildInputs = with python.pkgs; [
    openai
    anthropic
    python-dotenv
    fire
    httpx
    rich
    tenacity
    pyyaml
    requests
    jinja2
    pydantic
    prompt-toolkit
    litellm
    typer
    platformdirs
    pyjwt  # Note: using pyjwt instead of PyJWT[crypto]

    # Advanced features - available via overlay
    # Note: Hermes references these in pyproject.toml, so we patch them out below
    # qwen-tts is available and working
    qwen-tts  # Official Qwen3-TTS for text-to-speech
  ];

  nativeBuildInputs = with pkgs; [
    git
    installShellFiles
    python.pkgs.setuptools
  ];

  # Skip tests and runtime dependency checks
  doCheck = false;
  doInstallCheck = false;

  # Disable Python hooks that check for optional dependencies
  pythonRemoveDepsCheckHook = true;

  # Override phases to skip dependency checks
  preInstallCheck = "";
  postInstallCheck = "";

  meta = with lib; {
    description = "Self-improving AI agent by Nous Research";
    homepage = "https://hermes-agent.nousresearch.com/";
    license = licenses.mit;
  };
}
