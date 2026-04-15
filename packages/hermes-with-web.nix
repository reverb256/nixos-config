# Hermes Agent with web dashboard frontend built in
#
# Takes the official hermes-agent package and injects the Vite-built
# web_dist into the read-only nix store path by creating a wrapper
# that adds a PYTHONPATH override.
{
  pkgs,
  hermes-pkg,
  web-dist,
}:
pkgs.runCommand "hermes-agent-with-web-${hermes-pkg.version or "0.9.0"}" {
  nativeBuildInputs = [ pkgs.makeWrapper ];
} ''
  mkdir -p $out/bin

  # Wrap hermes to inject web_dist into the hermes_cli package directory
  # We can't modify the nix store, so we use a sitecustomize approach:
  # Create a small python package that, when imported, patches web_server.WEB_DIST
  mkdir -p $out/lib/python3.11/site-packages/_hermes_web_patch
  cat > $out/lib/python3.11/site-packages/_hermes_web_patch/__init__.py << 'EOF'
import importlib
import pathlib

def _patch_web_dist():
    try:
        mod = importlib.import_module("hermes_cli.web_server")
        mod.WEB_DIST = pathlib.Path("${web-dist}")
    except Exception:
        pass

_patch_web_dist()
EOF

  # Wrapper for hermes that adds our patch to PYTHONPATH
  makeWrapper ${hermes-pkg}/bin/hermes $out/bin/hermes \
    --set HERMES_HOME "/var/lib/hermes/.hermes" \
    --prefix PYTHONPATH : "$out/lib/python3.11/site-packages"

  # Wrapper for hermes-agent
  if [ -e ${hermes-pkg}/bin/hermes-agent ]; then
    makeWrapper ${hermes-pkg}/bin/hermes-agent $out/bin/hermes-agent \
      --set HERMES_HOME "/var/lib/hermes/.hermes" \
      --prefix PYTHONPATH : "$out/lib/python3.11/site-packages"
  fi

  # Copy other binaries
  for bin in ${hermes-pkg}/bin/*; do
    name=$(basename "$bin")
    if [ ! -e "$out/bin/$name" ]; then
      ln -s $bin "$out/bin/$name"
    fi
  done

  # Copy share
  if [ -d ${hermes-pkg}/share ]; then
    cp -r ${hermes-pkg}/share $out/share
  fi
''
