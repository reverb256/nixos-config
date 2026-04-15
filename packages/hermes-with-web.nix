# Hermes Agent with web dashboard frontend injected into the Python env
#
# Creates a new Python environment that merges the hermes-agent venv
# with our built web_dist placed in the hermes_cli package directory.
{
  pkgs,
  hermes-pkg,
  web-dist,
}:
let
  # The hermes package wraps a venv. Find it from the binary.
  hermesVenv = pkgs.runCommand "hermes-venv-path" {} ''
    # The hermes wrapper script references the venv binary
    # Parse it from the bash wrapper
    VENV_PATH=$(cat ${hermes-pkg}/bin/hermes | grep -oP '/nix/store/[a-z0-9]+-hermes-agent-env' | head -1)
    if [ -z "$VENV_PATH" ]; then
      echo "ERROR: Could not find hermes-agent-env in wrapper" >&2
      exit 1
    fi
    echo -n "$VENV_PATH" > $out
  '';
in
pkgs.runCommand "hermes-agent-with-web-${hermes-pkg.version or "0.9.0"}" {
  nativeBuildInputs = [ pkgs.makeWrapper ];
} ''
  mkdir -p $out/bin

  VENV=$(<${hermesVenv})

  # Copy the entire hermes_cli package from the venv and add web_dist
  HERMES_CLI="$VENV/lib/python3.11/site-packages/hermes_cli"

  # Create our overlay site-packages directory
  OVERLAY="$out/lib/python3.11/site-packages"
  mkdir -p "$OVERLAY"

  # Create a .pth file pointing to the original venv site-packages
  echo "$VENV/lib/python3.11/site-packages" > "$OVERLAY/00-hermes-venv.pth"

  # Create the hermes_cli/web_dist directory with our built frontend
  # NO __init__.py — we rely on the .pth file to make the venv's hermes_cli
  # findable, and the web_dist dir just needs to exist at the right path.
  # The WEB_DIST = Path(__file__).parent / "web_dist" check looks at
  # the venv's hermes_cli/__init__.py's parent, not ours.
  # So we need to put web_dist into the VENV's hermes_cli directory.
  # But that's read-only. Instead, create a symlink farm.
  mkdir -p "$OVERLAY/hermes_cli"
  cp -r ${web-dist}/* "$OVERLAY/hermes_cli/web_dist/"
  # Symlink all other files from the venv's hermes_cli into our overlay
  for f in $VENV/lib/python3.11/site-packages/hermes_cli/*; do
    name=$(basename "$f")
    if [ "$name" != "web_dist" ] && [ ! -e "$OVERLAY/hermes_cli/$name" ]; then
      ln -s "$f" "$OVERLAY/hermes_cli/$name"
    fi
  done

  # Wrap hermes binaries with our overlay in PYTHONPATH (takes precedence)
  for bin in ${hermes-pkg}/bin/*; do
    name=$(basename "$bin")
    makeWrapper "$bin" "$out/bin/$name" \
      --prefix PYTHONPATH : "$OVERLAY" \
      --set HERMES_HOME "/var/lib/hermes/.hermes"
  done

  # Copy share
  if [ -d ${hermes-pkg}/share ]; then
    cp -r ${hermes-pkg}/share $out/share
  fi
''
