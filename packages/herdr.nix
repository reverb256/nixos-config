{ lib, writeShellScriptBin, curl, fetchurl }:

let
  pname = "herdr";
  version = "0.7.3";
  src = fetchurl {
    url = "https://github.com/ogulcancelik/herdr/releases/download/v${version}/herdr-linux-x86_64";
    sha256 = "0aPv5Oo+f65pjA5eMB1gjJcP9RhtnMUFXvpP6DC1YXM=";
  };
in
writeShellScriptBin pname ''
  set -euo pipefail

  DATA_DIR="$HOME/.local/share/herdr"
  BIN_DIR="$HOME/.local/bin"
  BIN="$BIN_DIR/herdr"
  mkdir -p "$DATA_DIR" "$BIN_DIR"

  # Download binary on first run (self-updating — herdr handles its own updates)
  if [ ! -x "$BIN" ]; then
    echo "Downloading herdr v${version}..."
    ${curl}/bin/curl -sSL -o "$BIN" "${src}"
    chmod +x "$BIN"
  fi

  # Ensure config has auto-update enabled
  CONFIG_DIR="$HOME/.config/herdr"
  CONFIG_FILE="$CONFIG_DIR/config.toml"
  mkdir -p "$CONFIG_DIR"
  if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << 'CONFIG_EOF'
[update]
channel = "stable"
version_check = true
manifest_check = true

[ui.sound]
enabled = false
CONFIG_EOF
  fi

  exec "$BIN" "$@"
''
