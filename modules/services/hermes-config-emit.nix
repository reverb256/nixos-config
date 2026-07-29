# Hermes Nix-managed config.yaml emitter — rewrites providers + fallback_providers
# top-level keys at boot from Nix expressions.
# Extracted from modules/services/hermes-cli.nix on 2026-07-29
# per Phase 3 de-monolith plan.
#
# Gated by config.services.hermes-cli.managedConfig.
# Dependencies: config.services.hermes-cli (user, managedProviders,
#   managedFallbackProviders), python3-with-pyyaml.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.hermes-cli;
in lib.mkIf (cfg.enable && cfg.managedConfig) {
  systemd.services.hermes-config-emit = {
    description = "Emit Nix-managed sections of hermes config.yaml";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];

    path = with pkgs; [(python3.withPackages (p: [p.pyyaml])) coreutils gnugrep];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      RemainAfterExit = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = ["/home/${cfg.user}/.hermes"];

      ExecStart = let
        managedProvidersJson =
          pkgs.writeText "hermes-managed-providers.json"
          (builtins.toJSON cfg.managedProviders);
        managedFallbackJson =
          pkgs.writeText "hermes-managed-fallback.json"
          (builtins.toJSON cfg.managedFallbackProviders);
      in pkgs.writeShellScript "hermes-config-emit" ''
        set -euo pipefail

        HERMES_CONFIG="/home/${cfg.user}/.hermes/config.yaml"

        if [ ! -f "$HERMES_CONFIG" ]; then
          echo "[hermes-config-emit] No config.yaml found at $HERMES_CONFIG"
          echo "[hermes-config-emit] Skipping — emit requires an existing hand-maintained file"
          exit 0
        fi

        MANAGED_TMP=$(mktemp /tmp/hermes-managed-XXXXXX.yaml)
        trap 'rm -f "$MANAGED_TMP"' EXIT

        python3 - <<PYEOF > "$MANAGED_TMP"
import sys, json
try:
    import yaml
except ImportError:
    print("yaml module not available; aborting hermes-config-emit", file=sys.stderr)
    sys.exit(1)

with open("${managedProvidersJson}") as f:
    managed_providers = json.load(f)
with open("${managedFallbackJson}") as f:
    managed_fallback = json.load(f)

doc = {}
if managed_providers:
    doc["providers"] = managed_providers
if managed_fallback:
    doc["fallback_providers"] = managed_fallback

yaml.safe_dump(
    doc,
    stream=sys.stdout,
    sort_keys=False,
    default_flow_style=False,
    allow_unicode=True,
)
PYEOF

        MERGED_TMP=$(mktemp /tmp/hermes-emit-merged-XXXXXX.yaml)

        python3 - <<PYEOF
import sys, json, os
import yaml

with open("$HERMES_CONFIG") as f:
    existing = yaml.safe_load(f) or {}

with open("$MANAGED_TMP") as f:
    managed = yaml.safe_load(f) or {}

for k, v in managed.items():
    existing[k] = v

with open("$MERGED_TMP", "w") as f:
    yaml.safe_dump(existing, f, sort_keys=False, default_flow_style=False, allow_unicode=True)
PYEOF

        if cmp -s "$MERGED_TMP" "$HERMES_CONFIG"; then
          echo "[hermes-config-emit] config.yaml unchanged (managed sections already in sync)"
        else
          cp "$HERMES_CONFIG" "$HERMES_CONFIG.bak.$(date +%s)" 2>/dev/null || true
          mv "$MERGED_TMP" "$HERMES_CONFIG"
          echo "[hermes-config-emit] ✓ Wrote managed sections (backup kept with .bak.<unix-ts> suffix)"
        fi

        chown ${cfg.user}:users "$HERMES_CONFIG" 2>/dev/null || true
        chmod 600 "$HERMES_CONFIG" 2>/dev/null || true

        rm -f "$MANAGED_TMP" "$MERGED_TMP"
      '';
    };
  };
}
