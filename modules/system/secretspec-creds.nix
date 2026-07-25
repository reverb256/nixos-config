# ─────────────────────────────────────────────────────────────────
# secretspec-creds — Phase 4 SecretSpec credential provisioning.
#
# At activation, decrypts each sops file via `sops -d --extract '["data"]'`
# and writes the resolved value to the declared /run/secrets/ path.
#
# Uses sops CLI directly (not secretspec-provider-sops subprocess) to
# avoid provider extraction bugs. The `--extract '["data"]'` flag works
# for both binary-format and YAML-format sops files.
# -----------------------------------------------------------------
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.secretspec-creds;

  writeScript = pkgs.writeShellScript "secretspec-write-creds" ''
    set -euo pipefail
    LOG="/var/log/secretspec-creds.log"
    log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

    SOPS="${pkgs.sops}/bin/sops"
    fail=0
    CONFIG="/etc/nixos/.sops.yaml"
    SECRETS_DIR="/etc/nixos/secrets"

    write_secret() {
      local name="$1" path="$2" file="$3" mode="$4" owner="$5" group="$6"
      log "Decrypting ${file} → ${path} ..."
      local value
      value=$("$SOPS" -d --config "$CONFIG" --extract '["data"]' "$SECRETS_DIR/$file" 2>>"$LOG") || {
        log "FAILED: sops -d ${file} (exit $?)"
        fail=1; return
      }
      if [ -z "$value" ] || [ "$value" = "null" ]; then
        log "FAILED: ${file} resolved to empty/null"
        fail=1; return
      fi
      install -D -m "$mode" -o "$owner" -g "$group" \
        <(printf '%s' "$value") "$path" 2>>"$LOG" || {
        log "FAILED: install ${path}"; fail=1; return
      }
      log "Wrote ${path} ($(wc -c < "$path") bytes)"
    }

    ${concatStringsSep "\n" (mapAttrsToList (name: entry:
      "write_secret ${name} ${entry.path} ${entry.file} ${toString entry.mode} ${entry.owner} ${entry.group}"
    ) cfg.secrets)}

    if [ "$fail" = 1 ]; then
      log "One or more secrets failed — see journalctl -u secretspec-creds"
      exit 1
    fi
    log "All ${builtins.toString (builtins.length (builtins.attrNames cfg.secrets))} secrets written."
  '';
in {
  options.services.secretspec-creds = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable SecretSpec credential provisioning at activation.";
    };

    secrets = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          path = mkOption { type = types.str; };
          file = mkOption { type = types.str; description = "Relative path under /etc/nixos/secrets/"; };
          mode = mkOption { type = types.str; default = "0444"; };
          owner = mkOption { type = types.str; default = "root"; };
          group = mkOption { type = types.str; default = "root"; };
        };
      });
      default = {};
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ sops ];

    systemd.services.secretspec-creds = {
      description = "SecretSpec credential provisioning — sops-d + write /run/secrets/*";
      documentation = [ "https://secretspec.dev" ];
      wantedBy = ["multi-user.target"];
      before = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = writeScript;
        Environment = [ "SOPS_AGE_KEY_FILE=/etc/nixos/.age/key.txt" ];
        StandardOutput = "journal";
        StandardError = "journal";
        TimeoutStartSec = "5min";
      };
    };
  };
}
