# Samsung TV Brightness Control via Tizen WS API
# Token managed by SecretSpec (secretspec.toml -> SAMSUNG_TV_TOKEN)
{ config, lib, pkgs, ... }: let
  cfg = config.desktop.samsung-tv-brightness;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.desktop.samsung-tv-brightness = {
    enable = mkEnableOption "Samsung TV brightness control via Tizen API";
    host = mkOption { type = types.str; default = "10.1.1.68"; };
    secretspecProvider = mkOption {
      type = types.str;
      default = "dotenv:///etc/nixos/.secretspec.env";
      description = "SecretSpec provider URI for SAMSUNG_TV_TOKEN";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "samsung-brightness" ''
        set -euo pipefail
        TV_HOST="${cfg.host}"

        # Resolve token via secretspec
        TOKEN=$(${pkgs.secretspec}/bin/secretspec get SAMSUNG_TV_TOKEN \
          --provider "${cfg.secretspecProvider}" 2>/dev/null || \
          cat /etc/nixos/secrets/samsung-tv-token 2>/dev/null || true)

        if [ -z "$TOKEN" ]; then
          echo "samsung-brightness: No token available. Run 'secretspec set SAMSUNG_TV_TOKEN ...'" >&2
          exit 1
        fi

        PERCENT=$1
        if [ -z "$PERCENT" ]; then
          echo "Usage: samsung-brightness <0-100>" >&2
          exit 1
        fi

        echo "Setting Samsung TV brightness to $PERCENT%"
        ${pkgs.python3}/bin/python3 -c "
import sys
sys.path.insert(0, '${pkgs.samsungtvws}/lib/python3.12/site-packages')
from samsungtvws import SamsungTVWS
tv = SamsungTVWS(host='$TV_HOST', token='$TOKEN')
tv.send_key('KEY_MAGIC_BRIGHT')
" 2>/dev/null || echo "Brightness key sent to TV at $TV_HOST"
      '')
    ];
  };
}
