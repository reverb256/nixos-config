{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.auto-secrets;
  secretsDir = "/var/lib/secrets";
in {
  options.services.auto-secrets = {
    enable = lib.mkEnableOption "automatic secret generation";

    secrets = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            owner = lib.mkOption {
              type = lib.types.str;
              default = "root";
              example = "grafana";
              description = "Owner of the secret file";
            };

            group = lib.mkOption {
              type = lib.types.str;
              default = "root";
              example = "grafana";
              description = "Group of the secret file";
            };

            mode = lib.mkOption {
              type = lib.types.str;
              default = "0400";
              example = "0400";
              description = "File permissions (default: owner read only)";
            };

            length = lib.mkOption {
              type = lib.types.int;
              default = 64;
              example = 32;
              description = "Length of generated password (hex chars, so 64 = 256-bit entropy)";
            };

            regenerate = lib.mkOption {
              type = lib.types.bool;
              default = false;
              example = true;
              description = "Regenerate secret if it already exists (useful for rotation)";
            };
          };
        }
      );
      default = {};
      description = "Secrets to generate automatically";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.secrets != {}) {
    systemd.tmpfiles.rules = [
      "d ${secretsDir} 0700 root root -"
    ];

    systemd.services =
      lib.mapAttrs' (name: secretCfg: {
        name = "auto-secret-${name}";
        value = {
          description = "Generate secret: ${name}";
          wantedBy = ["multi-user.target"];
          before = lib.optional (secretCfg.owner != "root") "systemd-user-sessions.service";
          after = ["local-fs.target"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;

            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [secretsDir];
            UMask = "0077";

            ExecStart = pkgs.writeShellScript "generate-secret-${name}" ''
              set -euo pipefail

              SECRET_PATH="${secretsDir}/${name}"
              SECRET_LENGTH=${toString secretCfg.length}

              if [ -f "$SECRET_PATH" ] && [ "${
                if secretCfg.regenerate
                then "1"
                else "0"
              }" = "0" ]; then
                echo "Secret ${name} already exists, skipping generation"
                exit 0
              fi

              echo "Generating secret ${name} ($SECRET_LENGTH hex chars = $((SECRET_LENGTH * 4))-bit entropy)..."
              ${pkgs.openssl}/bin/openssl rand -hex $((SECRET_LENGTH / 2)) > "$SECRET_PATH.tmp"

              chmod ${secretCfg.mode} "$SECRET_PATH.tmp"

              mv "$SECRET_PATH.tmp" "$SECRET_PATH"

              chown ${secretCfg.owner}:${secretCfg.group} "$SECRET_PATH"

              echo "Secret ${name} generated successfully at $SECRET_PATH"
            '';
          };
        };
      })
      cfg.secrets;

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "secret-status" ''
        echo "Auto-generated secrets status:"
        echo "================================"
        for secret in ${lib.concatStringsSep " " (lib.attrNames cfg.secrets)}; do
          if [ -f "${secretsDir}/$secret" ]; then
            perms=$(stat -c "%a %U:%G" "${secretsDir}/$secret")
            size=$(stat -c "%s" "${secretsDir}/$secret")
            echo "✅ $secret: exists ($size bytes, $perms)"
          else
            echo "❌ $secret: NOT GENERATED"
          fi
        done
      '')
    ];
  };
}
