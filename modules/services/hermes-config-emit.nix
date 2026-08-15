# Hermes Nix-managed config.yaml emitter — rewrites providers + fallback_providers
# top-level keys at boot from Nix expressions.
# Extracted from modules/services/hermes-cli.nix on 2026-07-29
# per Phase 3 de-monolith plan.
#
# Gated by config.services.hermes-cli.managedConfig.
# Dependencies: config.services.hermes-cli (user, managedProviders,
#   managedFallbackProviders), python3-with-pyyaml.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-cli;
in
  lib.mkIf (cfg.enable && cfg.managedConfig) {
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
          managedA2aJson =
            pkgs.writeText "hermes-managed-a2a-agents.json"
            (builtins.toJSON cfg.managedA2aAgents);
          managedGatewayA2aJson =
            pkgs.writeText "hermes-managed-gateway-a2a.json"
            (builtins.toJSON cfg.managedGatewayA2a);
        in
          pkgs.writeShellScript "hermes-config-emit" ''
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
            with open("${managedA2aJson}") as f:
                managed_a2a_agents = json.load(f)
            with open("${managedGatewayA2aJson}") as f:
                managed_gateway_a2a = json.load(f)

            doc = {}
            if managed_providers:
                doc["providers"] = managed_providers
            if managed_fallback:
                doc["fallback_providers"] = managed_fallback
            if managed_a2a_agents:
                doc["a2a_agents"] = managed_a2a_agents
            if managed_gateway_a2a is not None:
                doc["gateway"] = {
                    **(doc.get("gateway") or {}),
                    "platforms": {
                        **((doc.get("gateway") or {}).get("platforms") or {}),
                        "a2a": managed_gateway_a2a,
                    },
                }

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
                if k == "gateway":
                    # Deep-merge gateway sections so other platforms
                    # (telegram, discord, etc.) survive the emit.
                    existing_gw = existing.get("gateway") or {}
                    managed_plat = v.get("platforms") or {}
                    existing_plat = existing_gw.get("platforms") or {}
                    existing_gw = dict(existing_gw)
                    existing_gw["platforms"] = {**existing_plat, **managed_plat}
                    existing["gateway"] = existing_gw
                elif k == "a2a_agents":
                    # Deep-merge per-peer so token values (hermes-owned,
                    # NEVER in Nix store) survive the emit while peer
                    # structure (url/capabilities/timeout) is Nix-managed.
                    existing_peers = existing.get("a2a_agents") or {}
                    merged_peers = {}
                    for peer, peer_cfg in v.items():
                        merged_peers[peer] = {
                            **peer_cfg,
                            **existing_peers.get(peer, {}),
                        }
                    # peers removed from Nix no longer emit; keep any peers
                    # that were never managed (preserve unknown/legacy peers).
                    for peer, peer_cfg in existing_peers.items():
                        merged_peers.setdefault(peer, peer_cfg)
                    existing["a2a_agents"] = merged_peers
                else:
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
