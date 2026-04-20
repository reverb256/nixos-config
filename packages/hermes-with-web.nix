# Hermes Agent with web dashboard frontend + fastapi/uvicorn injected
#
# Creates a Python overlay that merges the hermes-agent venv with:
# 1. The built web_dist SPA frontend
# 2. fastapi + uvicorn (optional [web] extras needed by `hermes dashboard`)
{
  pkgs,
  hermes-pkg,
  web-dist,
}:
let
  # The hermes package wraps a venv. Find it from the binary.
  hermesVenv = pkgs.runCommand "hermes-venv-path" {} ''
    VENV_PATH=$(cat ${hermes-pkg}/bin/hermes | grep -oP '/nix/store/[a-z0-9]+-hermes-agent-env' | head -1)
    if [ -z "$VENV_PATH" ]; then
      echo "ERROR: Could not find hermes-agent-env in wrapper" >&2
      exit 1
    fi
    echo -n "$VENV_PATH" > $out
  '';
in
pkgs.runCommand "hermes-agent-with-web-${hermes-pkg.version or "0.10.0"}" {
  nativeBuildInputs = [ pkgs.makeWrapper pkgs.curl pkgs.unzip ];
  buildInputs = [ hermes-pkg ];
} ''
  mkdir -p $out/bin

  VENV=$(<${hermesVenv})

  # Create our overlay site-packages directory
  OVERLAY="$out/lib/python3.11/site-packages"
  mkdir -p "$OVERLAY"

  # Create a .pth file pointing to the original venv site-packages
  echo "$VENV/lib/python3.11/site-packages" > "$OVERLAY/00-hermes-venv.pth"

  # Create the hermes_cli/web_dist directory with our built frontend
  mkdir -p "$OVERLAY/hermes_cli/web_dist"
  cp -r ${web-dist}/* "$OVERLAY/hermes_cli/web_dist/"
  # Symlink all other files from the venv's hermes_cli into our overlay
  for f in $VENV/lib/python3.11/site-packages/hermes_cli/*; do
    name=$(basename "$f")
    if [ "$name" != "web_dist" ] && [ ! -e "$OVERLAY/hermes_cli/$name" ]; then
      ln -s "$f" "$OVERLAY/hermes_cli/$name"
    fi
  done

  # Download fastapi+uvicorn wheels from PyPI (pure Python packages)
  # These are needed by `hermes dashboard` but not included in the base venv
  for pkg in fastapi-0.128.0 uvicorn-0.40.0 starlette-0.47.2 anyio-4.10.0 sniffio-1.3.1 idna-3.10 click-8.3.0 h11-0.16.0; do
    name="''${pkg%-*}"
    ${pkgs.curl}/bin/curl -sL "https://pypi.org/simple/''${name}/" | grep -oP "href=\"[^\"]+''${pkg}-py3-none-any.whl[^\"]*\"" | head -1 | grep -oP 'https://[^"]+' | head -1 | xargs -I{} ${pkgs.curl}/bin/curl -sL "{}" -o /tmp/''${pkg}.whl
    ${pkgs.unzip}/bin/unzip -qo /tmp/''${pkg}.whl -d "$OVERLAY"
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
