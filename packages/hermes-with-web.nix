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
    head -20 ${hermes-pkg}/bin/hermes | grep -oP '/nix/store/[a-z0-9]+-hermes-agent-env' > $out
  '';
in
pkgs.runCommand "hermes-agent-with-web-${hermes-pkg.version or "0.9.0"}" {
  nativeBuildInputs = [ pkgs.makeWrapper ];
} ''
  mkdir -p $out/bin

  VENV=$(cat ${hermesVenv} | tr -d '\n')

  # Copy the entire hermes_cli package from the venv and add web_dist
  HERMES_CLI="$VENV/lib/python3.11/site-packages/hermes_cli"

  # Create our overlay site-packages directory
  OVERLAY="$out/lib/python3.11/site-packages"
  mkdir -p "$OVERLAY"

  # Create a .pth file pointing to the original venv site-packages
  echo "$VENV/lib/python3.11/site-packages" > "$OVERLAY/00-hermes-venv.pth"

  # Create the hermes_cli/web_dist directory with our built frontend
  mkdir -p "$OVERLAY/hermes_cli/web_dist"
  cp -r ${web-dist}/* "$OVERLAY/hermes_cli/web_dist/"

  # Create hermes_cli as a namespace package that takes precedence
  # Python will find our hermes_cli/web_dist first, then fall through to venv for other modules
  cat > "$OVERLAY/hermes_cli/__init__.py" << 'EOF'
# Namespace package - extends the hermes_cli from the venv
from pkgutil import extend_path
__path__ = extend_path(__path__, __name__)
EOF

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
