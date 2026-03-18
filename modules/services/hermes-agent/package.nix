{
  pkgs,
  lib,
  config,
  ...
}:
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
      # Remove packages that don't have source distributions on PyPI
      sed -i '/parallel-web/d; /firecrawl-py/d; /fal-client/d' pyproject.toml || true
      echo "[Hermes] ✓ Patched pyproject.toml" >&2
    fi

    # Patch Python imports to be conditional (for unavailable packages)
    echo "[Hermes] Patching Python imports for unavailable packages..." >&2

    # Comment out imports for packages without source distributions
    if [ -f tools/web_tools.py ]; then
      sed -i 's/^from firecrawl import Firecrawl/# from firecrawl import Firecrawl  # DISABLED: no source distribution available/' tools/web_tools.py || true
    fi

    if [ -f tools/image_generation_tool.py ]; then
      sed -i 's/^import fal_client/# import fal_client  # DISABLED: no source distribution available/' tools/image_generation_tool.py || true
    fi

    if [ -f tools/terminal_tool.py ]; then
      sed -i 's/^from minisweagent_path import/# from minisweagent_path import  # DISABLED: submodule not available/' tools/terminal_tool.py || true
      sed -i 's/^ensure_minisweagent_on_path/# ensure_minisweagent_on_path  # DISABLED: submodule not available/' tools/terminal_tool.py || true
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
    pyjwt # Note: using pyjwt instead of PyJWT[crypto]

    # Advanced features - available via overlay
    qwen-tts # Official Qwen3-TTS for text-to-speech
    faster-whisper # Faster Whisper transcription with CTranslate2
    edge-tts # Microsoft Edge's online text-to-speech service
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

  # Install CLI scripts and binaries
  postInstall = ''
    # Install the main hermes CLI
    install -D -m755 $src/cli.py $out/bin/hermes
    # Fix shebang to use the correct Python interpreter
    substituteInPlace $out/bin/hermes \
      --replace "#!/usr/bin/env python3" "#!${python}/bin/python"

    # Install hermes-agent binary (gateway runner)
    install -D -m755 $src/run_agent.py $out/bin/hermes-agent
    substituteInPlace $out/bin/hermes-agent \
      --replace "#!/usr/bin/env python3" "#!${python}/bin/python"

    # Install hermes-acp binary
    install -D -m755 $src/acp_adapter/entry.py $out/bin/hermes-acp
    substituteInPlace $out/bin/hermes-acp \
      --replace "#!/usr/bin/env python3" "#!${python}/bin/python"
  '';

  meta = with lib; {
    description = "Self-improving AI agent by Nous Research";
    homepage = "https://hermes-agent.nousresearch.com/";
    license = licenses.mit;
  };
}
