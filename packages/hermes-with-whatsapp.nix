# packages/hermes-with-whatsapp.nix
#
# Wraps hermes-agent to inject the WhatsApp bridge into the Python package
# directory, where both the CLI (`hermes whatsapp`) and the gateway adapter
# discover it via Path(__file__).resolve().parents[1] / "scripts/whatsapp-bridge/".

{
  pkgs,
  hermes-pkg,
  whatsapp-bridge,
}:

let
  hermesVenv = pkgs.runCommand "hermes-venv-path" {} ''
    VENV_PATH=$(cat ${hermes-pkg}/bin/hermes | grep -oP '/nix/store/[a-z0-9]+-hermes-agent-env' | head -1)
    if [ -z "$VENV_PATH" ]; then
      echo "ERROR: Could not find hermes-agent-env in wrapper" >&2
      exit 1
    fi
    echo -n "$VENV_PATH" > $out
  '';

in
pkgs.runCommand "hermes-agent-with-whatsapp-${hermes-pkg.version or "0.10.0"}" {
  nativeBuildInputs = [ pkgs.makeWrapper ];
  buildInputs = [ hermes-pkg ];
} ''
  mkdir -p $out/bin $out/share

  VENV=$(<${hermesVenv})

  # Detect actual python version from the venv
  PYTHON_VER=$(ls "$VENV/lib/" | grep -oP 'python\d+\.\d+' | head -1)
  if [ -z "$PYTHON_VER" ]; then
    echo "ERROR: Could not detect Python version in $VENV/lib/" >&2
    ls "$VENV/lib/" >&2
    exit 1
  fi
  VENV_SITE="$VENV/lib/$PYTHON_VER/site-packages"
  echo "Using $VENV_SITE" >&2

  # Find hermes_cli in the venv
  HERMES_CLI_DIR="$VENV_SITE/hermes_cli"
  if [ ! -d "$HERMES_CLI_DIR" ]; then
    # Follow symlink if needed
    REAL=$(readlink -f "$HERMES_CLI_DIR" 2>/dev/null || true)
    if [ -d "$REAL" ]; then
      HERMES_CLI_DIR="$REAL"
    else
      echo "ERROR: hermes_cli not found at $VENV_SITE/hermes_cli" >&2
      exit 1
    fi
  fi

  # Create overlay site-packages
  OVERLAY="$out/lib/$PYTHON_VER/site-packages"
  mkdir -p "$OVERLAY"

  # .pth so Python finds the original venv
  echo "$VENV_SITE" > "$OVERLAY/00-hermes-venv.pth"

  # Symlink all hermes_cli/* into our overlay
  mkdir -p "$OVERLAY/hermes_cli"
  for f in "$HERMES_CLI_DIR"/*; do
    name=$(basename "$f")
    if [ ! -e "$OVERLAY/hermes_cli/$name" ]; then
      ln -s "$f" "$OVERLAY/hermes_cli/$name"
    fi
  done

  # Inject WhatsApp bridge
  mkdir -p "$OVERLAY/scripts"
  ln -s ${whatsapp-bridge} "$OVERLAY/scripts/whatsapp-bridge"

  # Wrap binaries
  for bin in ${hermes-pkg}/bin/*; do
    name=$(basename "$bin")
    makeWrapper "$bin" "$out/bin/$name" \
      --prefix PYTHONPATH : "$OVERLAY"
  done

  # Copy share
  if [ -d ${hermes-pkg}/share ]; then
    cp -r ${hermes-pkg}/share $out/share
  fi
''
