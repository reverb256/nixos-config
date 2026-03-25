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
        sed -i '/parallel-web/d; /firecrawl-py/d; /fal-client/d; /edge-tts/d; /faster-whisper/d; /qwen-tts/d' pyproject.toml || true
        # Relax tenacity version constraint (allow 9.1.2)
        sed -i 's/tenacity<10,>=9\.1\.4/tenacity>=9.1/g' pyproject.toml || true
        echo "[Hermes] ✓ Patched pyproject.toml" >&2
      fi

      # Patch Python source files to make optional imports conditional
      echo "[Hermes] Patching Python source files for optional dependencies..." >&2

      # Patch tools/web_tools.py - make firecrawl import conditional
      if [ -f tools/web_tools.py ]; then
        echo "[Hermes] Patching tools/web_tools.py to make firecrawl import optional..." >&2
        # Find the line and wrap it with try/except (no ^ anchor - import has leading whitespace)
        sed -i 's/from firecrawl import Firecrawl/try:\n        from firecrawl import Firecrawl\n    except ImportError:\n        Firecrawl = None  # Optional dependency not available/' tools/web_tools.py || true
        echo "[Hermes] ✓ Patched firecrawl import" >&2
      fi

      # Patch tools/image_generation_tool.py - make fal_client import conditional
      if [ -f tools/image_generation_tool.py ]; then
        echo "[Hermes] Patching tools/image_generation_tool.py to make fal_client import optional..." >&2
        sed -i 's/import fal_client/try:\n    import fal_client\nexcept ImportError:\n    fal_client = None  # Optional dependency not available/' tools/image_generation_tool.py || true
        echo "[Hermes] ✓ Patched fal_client import" >&2
      fi

      # Patch tools/terminal_tool.py - make minisweagent import conditional
      if [ -f tools/terminal_tool.py ]; then
        echo "[Hermes] Patching tools/terminal_tool.py to make minisweagent import optional..." >&2
        # Comment out minisweagent import line
        sed -i 's/from minisweagent_path import/# from minisweagent_path import # Disabled - submodule not available/' tools/terminal_tool.py || true
        # Comment out ensure_minisweagent_on_path call
        sed -i 's/ensure_minisweagent_on_path()/# ensure_minisweagent_on_path()  # Disabled - submodule not available/' tools/terminal_tool.py || true
        echo "[Hermes] ✓ Patched minisweagent imports" >&2
      fi

      echo "[Hermes] ✓ Patched Python source files" >&2
    '';

    propagatedBuildInputs = with python.pkgs; [
      # Core dependencies only
      openai
      anthropic
      python-dotenv
      fire # web_scraper, async_scanner (CORE dependency, not optional)
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
      # - fal-client (image generation)
      # - edge-tts (TTS)
      # - faster-whisper (transcription)
      # - qwen-tts (TTS)
      # - firecrawl-py (web scraping, in [all] extras)
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

      # Patch optional imports using Python (more reliable than sed)
      echo "[Hermes] Patching optional dependencies with Python..." >&2
      ${python}/bin/python <<EOF
import os
import re

site_packages = "$out/${python.sitePackages}"

# Patch tools/web_tools.py - wrap firecrawl import
web_tools = os.path.join(site_packages, "tools/web_tools.py")
if os.path.exists(web_tools):
    with open(web_tools, 'r') as f:
        content = f.read()

    # Replace import with try/except wrapper
    content = re.sub(
        r'from firecrawl import Firecrawl',
        '''try:
        from firecrawl import Firecrawl
    except ImportError:
        Firecrawl = None  # Optional dependency not available''',
        content
    )

    with open(web_tools, 'w') as f:
        f.write(content)
    print("[Hermes] ✓ Patched firecrawl import", file=__import__('sys').stderr)

# Patch tools/image_generation_tool.py - wrap fal_client import
img_gen = os.path.join(site_packages, "tools/image_generation_tool.py")
if os.path.exists(img_gen):
    with open(img_gen, 'r') as f:
        content = f.read()

    content = re.sub(
        r'import fal_client',
        '''try:
    import fal_client
except ImportError:
    fal_client = None  # Optional dependency not available''',
        content
    )

    with open(img_gen, 'w') as f:
        f.write(content)
    print("[Hermes] ✓ Patched fal_client import", file=__import__('sys').stderr)

# Patch tools/terminal_tool.py - comment out minisweagent
terminal = os.path.join(site_packages, "tools/terminal_tool.py")
if os.path.exists(terminal):
    with open(terminal, 'r') as f:
        content = f.read()

    # Comment out minisweagent imports
    content = re.sub(
        r'from minisweagent_path import',
        '# from minisweagent_path import  # Disabled - submodule not available',
        content
    )
    # Comment out ensure_minisweagent_on_path call
    content = re.sub(
        r'ensure_minisweagent_on_path\(\)',
        '# ensure_minisweagent_on_path()  # Disabled - submodule not available',
        content
    )

    with open(terminal, 'w') as f:
        f.write(content)
    print("[Hermes] ✓ Patched minisweagent imports", file=__import__('sys').stderr)

print("[Hermes] ✓ All optional dependency patches applied", file=__import__('sys').stderr)
EOF

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
