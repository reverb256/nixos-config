# Hermes MCP servers systemd unit — merges Nix-defined mcp_servers
# from the mcp-server-registry into ~/.hermes/config.yaml at boot.
# Extracted from modules/services/hermes-cli.nix on 2026-07-29
# per Phase 3 de-monolith plan.
#
# Dependencies: config.services.hermes-cli (user),
#   config.lib.mcp-registry.hermesMcpYaml (single source of truth
#   from modules/services/mcp-server-registry.nix),
#   python3-with-ruamel-yaml.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-cli;
  useRegistry = config.services.mcp-registry.enable or false;

  # ruamel.yaml round-trip merge into Hermes config.yaml. Replaces the
  # line-by-line parser which broke on:
  #   - top-level `mcp_servers:` keys nested deeper in the document
  #   - YAML comments / quoted strings containing "mcp_servers:"
  #   - multi-line scalars / flow-style maps
  # ruamel preserves comments, ordering, and key structure on round-trip.
  mcpMergeScript = pkgs.writeText "hermes-mcp-merge.py" ''
    import os
    import shutil
    import sys
    import time
    from ruamel.yaml import YAML

    config_path = sys.argv[1]
    mcp_path = sys.argv[2]

    yaml = YAML()
    yaml.indent(mapping=2, sequence=4, offset=2)
    yaml.preserve_quotes = True

    if os.path.exists(config_path):
        try:
            with open(config_path) as f:
                data = yaml.load(f) or {}
        except Exception as e:
            ts = int(time.time())
            backup = f"{config_path}.bak.{ts}"
            shutil.copy2(config_path, backup)
            print(f"[hermes-mcp] FATAL: config.yaml parse failed: {e}", file=sys.stderr)
            print(f"[hermes-mcp] backed up to {backup}; refusing to overwrite", file=sys.stderr)
            sys.exit(1)
    else:
        data = {}

    if not os.path.exists(mcp_path):
        print(f"[hermes-mcp] FATAL: mcp block not found at {mcp_path}", file=sys.stderr)
        sys.exit(1)
    with open(mcp_path) as f:
        mcp_data = yaml.load(f) or {}
    if not mcp_data.get("mcp_servers"):
        print(f"[hermes-mcp] FATAL: mcp block has no mcp_servers mapping", file=sys.stderr)
        sys.exit(1)

    if "mcp_servers" in mcp_data:
        data["mcp_servers"] = mcp_data["mcp_servers"]

    with open(config_path, "w") as f:
        yaml.dump(data, f)
  '';
in
  lib.mkIf (cfg.enable && useRegistry) {
    systemd.services.hermes-mcp-servers = {
      restartIfChanged = true;
      description = "Inject declarative MCP servers into Hermes config (from mcp-server-registry)";
      after = ["network.target" "hermes-config-secrets.service"];
      wantedBy = ["multi-user.target"];

      path = with pkgs; [(python3.withPackages (p: [p.ruamel-yaml])) coreutils gnused];

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

        ExecStart = pkgs.writeShellScript "hermes-mcp-servers" ''
          set -euo pipefail

          for profile in "" analyst backend-eng frontend-eng maplespike-eng-1 maplespike-eng-2 maplespike-eng-3 ops researcher writer; do
            if [ -z "$profile" ]; then
              HERMES_CONFIG="/home/${cfg.user}/.hermes/config.yaml"
            else
              HERMES_CONFIG="/home/${cfg.user}/.hermes/profiles/$profile/config.yaml"
            fi

            if [ ! -f "$HERMES_CONFIG" ]; then
              echo "[hermes-mcp] No config.yaml for profile '$profile', skipping"
              continue
            fi

            echo "[hermes-mcp] Processing profile: $profile"

            MCP_TMP=$(mktemp /tmp/hermes-mcp-XXXXXX.yaml)
            cp ${config.lib.mcp-registry.hermesMcpYaml} "$MCP_TMP"

            python3 ${mcpMergeScript} "$HERMES_CONFIG" "$MCP_TMP"
            rm -f "$MCP_TMP"

            chown ${cfg.user}:users "$HERMES_CONFIG" 2>/dev/null || true
            chmod 600 "$HERMES_CONFIG" 2>/dev/null || true

            echo "[hermes-mcp] ✓ MCP servers configured for profile: $profile"
          done
        '';
      };
    };
  }
