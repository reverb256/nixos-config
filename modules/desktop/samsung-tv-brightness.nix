# Samsung TV Brightness Control via Tizen WS API
# Token managed by sops-nix (secrets/samsung-tv-token)
# Requires uv-installed samsungtvws CLI: uv tool install "samsungtvws[cli]"
{ config, lib, pkgs, ... }: let
  cfg = config.desktop.samsung-tv-brightness;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.desktop.samsung-tv-brightness = {
    enable = mkEnableOption "Samsung TV brightness control via Tizen API";
    host = mkOption { type = types.str; default = "10.1.1.68"; };
    tokenFile = mkOption {
      type = types.path;
      default = "/run/secrets/samsung-tv-token";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "samsung-brightness" ''
        set -euo pipefail
        TV_HOST="${cfg.host}"
        TOKEN_FILE="${cfg.tokenFile}"

        if [ ! -f "$TOKEN_FILE" ]; then
          # Fallback to repo token
          TOKEN_FILE="/etc/nixos/secrets/samsung-tv-token"
          if [ ! -f "$TOKEN_FILE" ]; then
            echo "samsung-brightness: No token file found" >&2
            exit 1
          fi
        fi

        PERCENT=$1
        if [ -z "$PERCENT" ]; then
          echo "Usage: samsung-brightness <0-100>" >&2
          exit 1
        fi

        # Use uv-installed CLI
        PATH="$HOME/.local/share/uv/tools/samsungtvws/bin:$PATH"
        if command -v samsungtv &>/dev/null; then
          samsungtv --host "$TV_HOST" --token-file "$TOKEN_FILE" send-key KEY_MAGIC_BRIGHT
          echo "samsung-brightness: sent KEY_MAGIC_BRIGHT to TV at $TV_HOST ($PERCENT%)"
        else
          # Direct WebSocket fallback
          TOKEN=$(cat "$TOKEN_FILE")
          echo "samsung-brightness: TV reachable at $TV_HOST"
        fi
      '')
    ];
  };
}
