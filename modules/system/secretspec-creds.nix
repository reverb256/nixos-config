# ─────────────────────────────────────────────────────────────────
# secretspec-creds — Phase 4 SecretSpec provisioning via systemd oneshot.
#
# Replaces sops-nix's sops-install-secrets builder as the activation-time
# secret writer. At activation, runs `secretspec get <NAME> --profile production`
# for each entry in `services.secretspec-creds.secrets` and writes the resolved
# value to the declared /run/secrets/ path.
#
# Designed to run IN PARALLEL with the sops registry. Both write the same
# files to /run/secrets/; whichever finishes first satisfies the consumer.
# Once verified, disable sops-secrets-registry and keep this module.
# -----------------------------------------------------------------
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.secretspec-creds;

  # Build a single shell script that resolves every secret via
  # `secretspec get` and writes each to its declared path.
  writeScript = pkgs.writeShellScript "secretspec-write-creds" ''
    set -euo pipefail
    LOG="/var/log/secretspec-creds.log"
    log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

    SECRETSPEC="${pkgs.secretspec}/bin/secretspec"
    fail=0

    ${concatStringsSep "\n" (mapAttrsToList (name: entry: ''
      log "Resolving ${name} → ${entry.path} ..."
      VALUE=$("$SECRETSPEC" get ${name} --profile production 2>>"$LOG") || {
        log "FAILED: secretspec get ${name} (exit $?)"
        fail=1; continue
      }
      if [ -z "$VALUE" ] || [ "$VALUE" = "null" ]; then
        log "FAILED: ${name} resolved to empty"
        fail=1; continue
      fi
      install -D -m ${toString entry.mode} -o ${entry.owner} -g ${entry.group} \
        <(printf '%s' "$VALUE") "${entry.path}" 2>>"$LOG" || {
        log "FAILED: write ${entry.path}"; fail=1; continue
      }
      log "Wrote ${entry.path} ($(wc -c < "${entry.path}") bytes)"
    '') cfg.secrets)}

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
      description = ''
        Enable SecretSpec provisioning at activation. When true, a systemd
        oneshot runs `secretspec get` for each declared secret and writes the
        resolved value to its target path.

        Run in parallel with the sops registry for validation (both write the
        same files). Once verified, disable sops-secrets-registry and keep this.
      '';
    };

    secrets = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          path = mkOption {
            type = types.str;
            description = "Absolute path to write (e.g. /run/secrets/context7-api-key)";
          };
          mode = mkOption { type = types.str; default = "0444"; };
          owner = mkOption { type = types.str; default = "root"; };
          group = mkOption { type = types.str; default = "root"; };
        };
      });
      default = {};
      description = ''
        Attrset mapping secretspec.toml secret names to their on-disk paths.
        Example:
          CONTEXT7_API_KEY = { path = "/run/secrets/context7-api-key";
            owner = "j_kro"; group = "users"; };
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      secretspec
      secretspec-provider-sops
    ];

    systemd.services.secretspec-creds = {
      description = "SecretSpec credential provisioning — resolve+write /run/secrets/*";
      documentation = [ "https://secretspec.dev" ];
      wantedBy = ["multi-user.target"];
      before = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = writeScript;
        Environment = [
          "SOPS_AGE_KEY_FILE=/etc/nixos/.age/key.txt"
          "SECRETSPEC_SOPS_PROVIDER_BIN=${pkgs.secretspec-provider-sops}/bin/secretspec-provider-sops-protocol"
        ];
        StandardOutput = "journal";
        StandardError = "journal";
        TimeoutStartSec = "5min";
      };
    };
  };
}
