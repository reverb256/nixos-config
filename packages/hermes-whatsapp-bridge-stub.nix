# packages/hermes-whatsapp-bridge-stub.nix
#
# Stub package that replaces the broken hermes-whatsapp-bridge
# when npm dependencies fail to build
{
  lib,
  pkgs,
  hermesSrc ? null,
  lockfile ? null,
}:
pkgs.runCommand "hermes-whatsapp-bridge-stub" {} ''
  mkdir -p $out
  # Create placeholder files instead of actual npm packages
  echo "# WhatsApp bridge stub - npm build disabled" > $out/bridge.js
  echo "# WhatsApp bridge stub - npm build disabled" > $out/allowlist.js
  echo '{"name": "hermes-whatsapp-bridge", "version": "0.0.0-stub"}' > $out/package.json
''
