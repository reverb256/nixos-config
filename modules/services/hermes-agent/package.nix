{
  pkgs,
  lib,
  config,
  ...
}: let
  # Use pkgs.python3 to get overlay packages (firecrawl-py, edge-tts, etc.)
  # instead of raw python313 which doesn't have the overlay applied
  python = pkgs.python3;
in
  python.pkgs.buildPythonApplication rec {
    pname = "hermes-agent";
    version = "0.1.0-unstable";
    format = "other";  # No standard Python build system

    # Disable dependency checks entirely
    doCheck = false;
    doInstallCheck = false;

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

      # Patch pyproject.toml to remove unavailable optional dependencies
      if [ -f pyproject.toml ]; then
        echo "[Hermes] Patching pyproject.toml to remove unavailable optional dependencies..." >&2
        # Remove optional packages that don't have source distributions on PyPI
        # These are in [all] extras but not available in Nixpkgs
        sed -i '/parallel-web/d; /firecrawl-py/d; /fal-client/d; /edge-tts/d; /faster-whisper/d; /qwen-tts/d' pyproject.toml || true
        # Relax tenacity version constraint (allow 9.1.2)
        sed -i 's/tenacity<10,>=9\.1\.4/tenacity>=9.1/g' pyproject.toml || true
        echo "[Hermes] ✓ Patched pyproject.toml" >&2
      fi
    '';

    propagatedBuildInputs = with python.pkgs; [
      # Core dependencies only (no optional extras like firecrawl, fal-client)
      openai
      anthropic
      python-dotenv
      httpx
      rich
      tenacity
      pyyaml
      requests
      jinja2
      pydantic
      prompt-toolkit
      typer
      platformdirs
      pyjwt # Note: using pyjwt instead of PyJWT[crypto]

      # Removed optional dependencies not available in Nixpkgs:
      # - fire (web_scraper, async_scanner)
      # - fal-client (image generation)
      # - edge-tts (TTS)
      # - faster-whisper (transcription)
      # - qwen-tts (TTS)
    ];

    nativeBuildInputs = with pkgs; [
      git
      installShellFiles
      python.pkgs.setuptools
    ];

    # Disable Python dependency validation
    # Note: pythonRelaxDeps removed - expects dist/ dir which doesn't exist
    # We manually patch pyproject.toml in postPatch phase instead
    dontUsePythonRuntimeDepsCheck = true;

    # Disable Python hooks that check for optional dependencies
    pythonRemoveDepsCheckHook = true;

    # Override phases to skip dependency checks
    preInstallCheck = "";
    postInstallCheck = "";
    pythonRuntimeDepsCheck = "";

    # Install CLI scripts and binaries
    postInstall = ''
      # Install the Python package first (so CLI tools can import it)
      PYTHONPATH=$out/${python.sitePackages}:$PYTHONPATH
      export PYTHONPATH
      mkdir -p $out/${python.sitePackages}

      # Copy the entire hermes_agent source to site-packages
      cp -r $src/* $out/${python.sitePackages}/

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
      mainProgram = "hermes-acp";
      platforms = lib.platforms.linux;
    };
  }
