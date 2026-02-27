# Auto-Secrets Module
# Automatically generates secure random passwords on first boot
# Passwords are stored in /var/lib/secrets/ and never committed to git
#
# Usage:
#   services.auto-secrets.secrets.grafana-admin = {
#     owner = "grafana";
#     group = "grafana";
#     length = 64;  # Optional, default 64 chars (256-bit entropy)
#   };
#
# Then reference: /var/lib/secrets/grafana-admin
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
              description = "Owner of the secret file";
            };

            group = lib.mkOption {
              type = lib.types.str;
              default = "root";
              description = "Group of the secret file";
            };

            mode = lib.mkOption {
              type = lib.types.str;
              default = "0400";
              description = "File permissions (default: owner read only)";
            };

            length = lib.mkOption {
              type = lib.types.int;
              default = 64;
              description = "Length of generated password (hex chars, so 64 = 256-bit entropy)";
            };

            regenerate = lib.mkOption {
              type = lib.types.bool;
              default = false;
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
    # Ensure secrets directory exists with proper permissions
    # 0700 restricts access to root only - prevents traversal by other users
    # Individual secret files have 0400 owner-only permissions
    systemd.tmpfiles.rules = [
      "d ${secretsDir} 0700 root root -"
    ];

    # Create a service for each secret
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

            # Security hardening
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [secretsDir];
            UMask = "0077";

            # Run as root initially, then chown
            ExecStart = pkgs.writeShellScript "generate-secret-${name}" ''
              set -euo pipefail

              SECRET_PATH="${secretsDir}/${name}"
              SECRET_LENGTH=${toString secretCfg.length}

              # Check if secret already exists and we're not regenerating
              if [ -f "$SECRET_PATH" ] && [ "${
                if secretCfg.regenerate
                then "1"
                else "0"
              }" = "0" ]; then
                echo "Secret ${name} already exists, skipping generation"
                exit 0
              fi

              # Generate cryptographically secure random password
              echo "Generating secret ${name} ($SECRET_LENGTH hex chars = $((SECRET_LENGTH * 4))-bit entropy)..."
              ${pkgs.openssl}/bin/openssl rand -hex $((SECRET_LENGTH / 2)) > "$SECRET_PATH.tmp"

              # Set permissions before moving
              chmod ${secretCfg.mode} "$SECRET_PATH.tmp"

              # Atomic move
              mv "$SECRET_PATH.tmp" "$SECRET_PATH"

              # Set ownership (requires root)
              chown ${secretCfg.owner}:${secretCfg.group} "$SECRET_PATH"

              echo "Secret ${name} generated successfully at $SECRET_PATH"
            '';
          };
        };
      })
      cfg.secrets;

    # Helper script to show secret status
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
