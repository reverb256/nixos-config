# packages/hermes-whatsapp-bridge.nix
#
# Builds the WhatsApp bridge Node.js package from the hermes-agent source.
#
# Strategy: patch package.json to use npm registry baileys (^7.0.0-rc.9, which
# has pre-compiled lib/) instead of the git dependency (needs TypeScript build).
# The lockfile is patched from the upstream original, replacing only the baileys
# git entry with the npm registry equivalent. Only libsignal remains as a git
# dep (pure JS, no build step).
#
# UPDATE PROCESS (when hermes-agent flake input updates):
#   1. If baileys version in upstream changed, check npm for the matching release:
#      npm view @whiskeysockets/baileys versions
#   2. Update the version in the sed replacement and the lockfile integrity hash
#   3. Regenerate lockfile: copy upstream's package-lock.json, patch baileys entry
#   4. Set npmDepsHash to lib.fakeHash, rebuild, copy the "got:" hash
#   5. If bridge.js API changed, check for compatibility
{
  lib,
  pkgs,
  hermesSrc,
  lockfile ? ./whatsapp-bridge-package-lock.json,
}: let
  # Patched source: replace baileys git dep with npm registry version in package.json
  # Uses generic regex to match any Baileys#commit hash
  patchedSrc = pkgs.runCommand "whatsapp-bridge-patched" {} ''
    mkdir -p $out
    cp ${hermesSrc}/scripts/whatsapp-bridge/bridge.js $out/
    cp ${hermesSrc}/scripts/whatsapp-bridge/allowlist.js $out/

    # Patched package.json: any baileys git dep → npm registry
    cat ${hermesSrc}/scripts/whatsapp-bridge/package.json | \
      sed 's|"@whiskeysockets/baileys": "WhiskeySockets/Baileys#[^"]*"|"@whiskeysockets/baileys": "^7.0.0-rc.9"|' \
      > $out/package.json

    # Lockfile patched from upstream original (baileys git → npm registry)
    cp ${lockfile} $out/package-lock.json
  '';
in
  pkgs.buildNpmPackage {
    pname = "hermes-whatsapp-bridge";
    version = "1.0.0";

    src = patchedSrc;

    npmDepsHash = "sha256-tc6ygFeY2PEpX4H9V9ENkjRtqIiHxT9mzkJHkTkYSuc=";
    npmDepsFetcherVersion = 2;

    forceGitDeps = true;
    makeCacheWritable = true;
    dontNpmBuild = true;
    npmFlags = ["--legacy-peer-deps"];

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r node_modules $out/node_modules
      cp bridge.js allowlist.js package.json $out/

      runHook postInstall
    '';

    meta = with lib; {
      description = "WhatsApp bridge for Hermes Agent using Baileys";
      license = licenses.mit;
      platforms = platforms.unix;
    };
  }
