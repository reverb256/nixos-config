{ lib, writeShellScriptBin, curl, fuse }:

let
  pname = "freebuff-desktop";
in
writeShellScriptBin pname ''
  set -euo pipefail

  APP_DIR="$HOME/.local/share/freebuff"
  APP_IMAGE="$APP_DIR/Freebuff-x86_64.AppImage"

  mkdir -p "$APP_DIR"

  # Update flag
  if [ $# -gt 0 ] && [ "$1" = "--update" ]; then
    echo "Updating Freebuff..."
    if [ -f "$APP_IMAGE" ]; then
      chmod +x "$APP_IMAGE"
      exec "$APP_IMAGE" --appimage-update
    fi
    rm -f "$APP_IMAGE"
  fi

  # Download if missing
  if [ ! -f "$APP_IMAGE" ]; then
    echo "Downloading Freebuff..."
    DOWNLOAD_URL=$(${lib.getExe curl} -sSLI -o /dev/null -w '%{url_effective}' \
      "https://freebuff.com/api/desktop/download/linux" 2>/dev/null || \
      echo "https://github.com/CodebuffAI/codebuff-community/releases/latest/download/Freebuff-0.0.18-linux-x86_64.AppImage")
    ${lib.getExe curl} -sSL -o "$APP_IMAGE" "$DOWNLOAD_URL"
    chmod +x "$APP_IMAGE"
    echo "Downloaded to $APP_IMAGE"
  fi

  # Run with FUSE if available, otherwise extract and run
  if [ -x "$APP_IMAGE" ]; then
    # inject fuse lib into LD_LIBRARY_PATH
    export LD_LIBRARY_PATH="${lib.getLib fuse}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec "$APP_IMAGE" --appimage-extract-and-run "$@"
  else
    echo "Error: Freebuff not found at $APP_IMAGE" >&2
    exit 1
  fi
''
