# Hermes config-secrets systemd unit — injects sops-nix + secretspec
# secrets into ~/.hermes/.env at boot.
# Extracted from modules/services/hermes-cli.nix on 2026-07-29
# per Phase 3 de-monolith plan.
#
# Dependencies: config.services.hermes-cli (user, secretspecEnvVarMappings,
#   nvidiaApiKeyFile, opencodeGoApiKeyFile, opencodeZenApiKeyFile,
#   gatewayUrl), pkgs.coreutils/gnused/gnugrep/jq/secretspec.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-cli;
  needed =
    cfg.nvidiaApiKeyFile
    != null
    || cfg.opencodeGoApiKeyFile != null
    || cfg.opencodeZenApiKeyFile != null
    || cfg.kilocodeApiKeyFile != null
    || cfg.hfTokenFile != null
    || cfg.githubTokenFile != null
    || cfg.secretspecEnvVarMappings != {};
in
  lib.mkIf (cfg.enable && needed) {
    systemd.services.hermes-config-secrets = {
      description = "Inject secrets into Hermes config (secretspec E2 + sops-nix E1)";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      path = with pkgs;
        [coreutils gnused gnugrep jq]
        ++ lib.optional (cfg.secretspecEnvVarMappings != {}) pkgs.secretspec;

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

        # Upstream secretspec 0.18.0 (fork deleted 2026-08-07): the native sops
        # provider reads the age identity from the sops CLI's standard env cars.
        Environment =
          lib.optional (cfg.secretspecEnvVarMappings != {})
          "SOPS_AGE_KEY_FILE=/etc/nixos/.age/key.txt";

        ExecStart = pkgs.writeShellScript "hermes-config-secrets" ''
          set -euo pipefail

          HERMES_CONFIG="/home/${cfg.user}/.hermes/config.yaml"

          if [ ! -f "$HERMES_CONFIG" ]; then
            echo "[hermes-config] No config.yaml found, skipping"
            exit 0
          fi

          GATEWAY_URL="${cfg.gatewayUrl}"
          sed -i "s|base_url: http://10\\.1\\.1\\.140:1235/v1|base_url: $GATEWAY_URL|g" "$HERMES_CONFIG"
          sed -i "s|base_url: http://10\\.4\\.[0-9]*\\.[0-9]*:1235/v1|base_url: $GATEWAY_URL|g" "$HERMES_CONFIG"
          sed -i "s|base_url: http://\\[IP_ADDRESS\\]:8080/v1|base_url: $GATEWAY_URL|g" "$HERMES_CONFIG"

          chown ${cfg.user}:users "$HERMES_CONFIG" 2>/dev/null || true
          chmod 600 "$HERMES_CONFIG" 2>/dev/null || true

          ENV_FILE="/home/${cfg.user}/.hermes/.env"

          ${lib.optionalString (cfg.opencodeZenApiKeyFile != null) ''
            OC_ZEN="${cfg.opencodeZenApiKeyFile}"
            if [ -f "$OC_ZEN" ] && [ -s "$OC_ZEN" ]; then
              ZEN_KEY="$(cat "$OC_ZEN")"
              grep -v '^OPENCODE_ZEN_API_KEY=\\|^#.*OPENCODE_ZEN_API_KEY=' "$ENV_FILE" > "$ENV_FILE".tmp 2>/dev/null || true
              echo "OPENCODE_ZEN_API_KEY=$ZEN_KEY" >> "$ENV_FILE".tmp
              sort -u "$ENV_FILE".tmp > "$ENV_FILE"
              chmod 600 "$ENV_FILE"
              chown ${cfg.user}:users "$ENV_FILE" 2>/dev/null || true
              echo "[hermes-config] ✓ OPENCODE_ZEN_API_KEY written to .env"
            fi
          ''}

          ${lib.optionalString (cfg.opencodeGoApiKeyFile != null) ''
            OC_GO="${cfg.opencodeGoApiKeyFile}"
            if [ -f "$OC_GO" ] && [ -s "$OC_GO" ]; then
              GO_KEY="$(cat "$OC_GO")"
              grep -v '^OPENCODE_GO_API_KEY=\\|^#.*OPENCODE_GO_API_KEY=' "$ENV_FILE" > "$ENV_FILE".tmp 2>/dev/null || true
              echo "OPENCODE_GO_API_KEY=$GO_KEY" >> "$ENV_FILE".tmp
              sort -u "$ENV_FILE".tmp > "$ENV_FILE"
              chmod 600 "$ENV_FILE"
              chown ${cfg.user}:users "$ENV_FILE" 2>/dev/null || true
              echo "[hermes-config] ✓ OPENCODE_GO_API_KEY written to .env"
            fi
          ''}

          ${lib.optionalString (cfg.nvidiaApiKeyFile != null) ''
            NV_KEY_PATH="${cfg.nvidiaApiKeyFile}"
            if [ -f "$NV_KEY_PATH" ] && [ -s "$NV_KEY_PATH" ]; then
              NV_KEY="$(cat "$NV_KEY_PATH")"
              grep -v '^NVIDIA_API_KEY=\\|^#.*NVIDIA_API_KEY=' "$ENV_FILE" > "$ENV_FILE".tmp 2>/dev/null || true
              echo "NVIDIA_API_KEY=$NV_KEY" >> "$ENV_FILE".tmp
              sort -u "$ENV_FILE".tmp > "$ENV_FILE"
              chmod 600 "$ENV_FILE"
              chown ${cfg.user}:users "$ENV_FILE" 2>/dev/null || true
              echo "[hermes-config] ✓ NVIDIA_API_KEY written to .env"
            fi
          ''}

          ${lib.optionalString (cfg.secretspecEnvVarMappings != {}) ''
            SECRETSPEC_MAP='${lib.toJSON cfg.secretspecEnvVarMappings}'
            SECRETSPEC_COUNT=${toString (builtins.length (builtins.attrNames cfg.secretspecEnvVarMappings))}
            echo "[hermes-config] Resolving $SECRETSPEC_COUNT route(s) via secretspec"
            printf '%s' "$SECRETSPEC_MAP" | jq -r 'to_entries[] | "\(.key)\t\(.value)"' | while IFS=$'\t' read -r route env_var; do
              value=$(secretspec get "$route" -f value 2>/dev/null || true)
              if [ -z "$value" ]; then
                echo "[hermes-config] WARN: secretspec get '$route' returned empty (sops provider / age key missing?)" >&2
                continue
              fi
              grep -v "^$env_var=" "$ENV_FILE" > "$ENV_FILE".tmp 2>/dev/null || true
              printf '%s=%s\n' "$env_var" "$value" >> "$ENV_FILE".tmp
              sort -u "$ENV_FILE".tmp > "$ENV_FILE"
              echo "[hermes-config] ✓ secretspec route '$route' -> $env_var"
            done
          ''}

          touch "$ENV_FILE"
          chmod 600 "$ENV_FILE" 2>/dev/null || true

          echo "[hermes-config] Done"
        '';
      };
    };
  }
