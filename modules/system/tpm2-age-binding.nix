# tpm2-age-binding.nix
#
# TPM 2.0 hardware-binding for the cluster age key used by SecretSpec/sops.
#
# Design:
# - On first boot (or after TPM/hardware reset), the module auto-seals the
#   host's age key to PCR 0+7 (firmware + Secure Boot state) at a persistent
#   TPM handle (no manual operator step).
# - On every subsequent boot, tpm2-unseal-age.service runs before
#   secretspec-creds.service, unseals the key to /run/secrets/cluster-age-key
#   (mode 0400, root only), then lets SecretSpec consume it via the
#   existing SOPS_AGE_KEY_FILE environment variable.
# - If the TPM is unavailable or the blob is missing, the service exits 0
#   (fail-open). SecretSpec then falls back to the plaintext key file.
#
# This module does NOT modify SecretSpec itself. It sits below it — the
# unsealed key file is consumed via the existing SOPS_AGE_KEY_FILE env var
# that secretspec-creds already sets.
#
# Scope: cluster-wide (zephyr, nexus, forge, sentry — all have TPM 2.0).
# Override per-host with `security.tpm2AgeBinding.primaryKeyPath` if needed.

{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.security.tpm2AgeBinding;
  runtimeKeyPath = "/run/secrets/cluster-age-key";
  sealedBlobDir = "/var/lib/tpm2-age-sealed";
  persistentHandle = "0x81000000";
in
{
  options.security.tpm2AgeBinding = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable TPM 2.0 hardware-binding for the cluster age key.
        Requires /dev/tpmrm0 (present on all cluster hosts).
        Auto-seals on first boot — no manual operator action needed.
      '';
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = runtimeKeyPath;
      defaultText = lib.literalExpression ''${runtimeKeyPath}'';
      description = ''
        Path that secretspec-creds should use for the age identity.
        Defaults to the TPM-unsealed runtime path.
      '';
    };

    primaryKeyPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/.age/key.txt";
      description = ''
        Source age key file to seal on first boot. Only needs to exist
        until the sealed blob is created. After that, only the TPM is
        required for unseal.
      '';
    };

    pcrList = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "0" "7" ];
      description = ''
        TPM PCRs to bind the sealed key to. Default [0 7] = firmware +
        Secure Boot state.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      tpm2-tools
      tpm2-tss
    ];

    systemd.tmpfiles.rules = [
      "d /run/secrets 0750 root root -"
    ];

    # The unseal service handles BOTH paths:
    # - If a sealed blob already exists at the persistent handle → unseal it
    # - If no sealed blob exists → auto-seal the source age key
    # This is "Apple easy": zero manual steps after deploy.
    systemd.services."tpm2-unseal-age" = {
      description = "TPM2: seal (if needed) + unseal the cluster age key at boot";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-logind.service" ];
      before = lib.mkIf (config.services ? secretspec-creds && config.services.secretspec-creds.enable)
        [ "secretspec-creds.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        pcrs="${(lib.concatStringsSep "," cfg.pcrList)}"
        pcr_arg="-l sha256:${(lib.concatStringsSep "," cfg.pcrList)}"

        # Check if a sealed blob already exists at the persistent handle
        existing_handle=$(tpm2_getcap handles-persistent 2>/dev/null | grep "0x81" || true)

        if [ -z "$existing_handle" ]; then
          # === AUTO-SEAL PATH: no existing blob found ===
          echo "tpm2-unseal-age: no sealed blob found, auto-sealing..."

          if [ ! -f "${cfg.primaryKeyPath}" ]; then
            echo "tpm2-unseal-age: source age key not found at ${cfg.primaryKeyPath}"
            echo "tpm2-unseal-age: cannot auto-seal. SecretSpec will use the static key."
            exit 0
          fi

          # Check if tpm2-tools is available (may not be on hosts without the module)
          if ! command -v tpm2_createprimary >/dev/null 2>&1; then
            echo "tpm2-unseal-age: tpm2-tools not installed, cannot seal"
            exit 0
          fi

          # Create primary key + policy + sealed object
          workdir=$(mktemp -d)
          trap 'rm -rf "$workdir"' EXIT

          tpm2_createprimary -C e -c "$workdir/primary.ctx"
          tpm2_startauthsession --policy-session -S "$workdir/policy"
          tpm2_policypcrs $pcr_arg -S "$workdir/policy"
          tpm2_policygetdigest -S "$workdir/policy" -o "$workdir/policy_digest"

          tpm2_create -C "$workdir/primary.ctx" -G sha256 \
            -u "$workdir/public.blob" -r "$workdir/private.blob" \
            -i "${cfg.primaryKeyPath}" -L "$workdir/policy"

          tpm2_load -C "$workdir/primary.ctx" \
            -u "$workdir/public.blob" -r "$workdir/private.blob" \
            -c "$workdir/sealed.ctx" -n "$workdir/name"

          tpm2_evictcontrol -C o -c "$workdir/sealed.ctx" ${persistentHandle}

          mkdir -p ${sealedBlobDir}
          printf "persistent_handle=${persistentHandle}\npmr_policy=pcr:%s\nsealed_at=%s\nauto_sealed=true\n" "$pcrs" "$(date -Iseconds)" \
            > "${sealedBlobDir}/meta"

          echo "tpm2-unseal-age: auto-sealed age key at handle ${persistentHandle}"
          existing_handle="${persistentHandle}"
        fi

        # === UNSEAL PATH: persist handle exists, unseal it ===
        tpm2_unseal -c "$existing_handle" > ${runtimeKeyPath}.tmp 2>/dev/null || {
          echo "tpm2-unseal-age: unseal failed (PCRs may not match current boot state)"
          echo "tpm2-unseal-age: SecretSpec will use the static age key fallback"
          rm -f ${runtimeKeyPath}.tmp
          exit 0
        }

        install -D -m 0400 -o root -g root ${runtimeKeyPath}.tmp ${runtimeKeyPath}
        rm -f ${runtimeKeyPath}.tmp
        echo "tpm2-unseal-age: age key unsealed to ${runtimeKeyPath}"
      '';
      path = with pkgs; [ tpm2-tools ];
    };

    # Override secretspec ageKeyFile to use the TPM-unsealed runtime path.
    # secretspec-creds and secretspec-validator modules are imported per-host
    # (see hosts/*/configuration.nix). mkForce ensures any host-level ageKeyFile
    # is overridden when the TPM module is active.
    services.secretspec-creds.ageKeyFile = lib.mkForce cfg.ageKeyFile;
    services.secretspec-validator.ageKeyFile = lib.mkForce cfg.ageKeyFile;
  };
}
