# tpm2-age-binding.nix
#
# TPM 2.0 hardware-binding for the cluster age key used by SecretSpec/sops.
#
# Design:
# - On first boot: auto-seals the host's age key to PCR 0+7 (firmware +
#   Secure Boot state) at a persistent TPM handle — no manual operator step.
# - On every subsequent boot: unseals the key to /run/secrets/cluster-age-key
#   (mode 0400, root only), then lets SecretSpec consume it via the existing
#   SOPS_AGE_KEY_FILE environment variable.
# - If unseal fails (PCR drift from firmware/BIOS/kernel changes) AND the
#   source age key is still present: evicts the stale blob, re-seals to the
#   new PCR state, then unseals — **automatic recovery**, zero manual steps.
# - If unseal fails AND the source key is unavailable: fails open (exit 0),
#   SecretSpec falls back to the plaintext key file.
#
# Re-seal is gated on the source key being present — an attacker who changed
# PCRs cannot re-seal without also having the plaintext age key.
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
        Auto-seals on first boot and auto-reseals on PCR drift —
        no manual operator action needed.
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
        Source age key file. Used for auto-seal on first boot and for
        auto-re-seal when PCRs drift. Only needs to exist at those times.
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

    # Single service: auto-seal on first boot, auto-re-seal on PCR drift,
    # fail-open if source key unavailable.
    systemd.services."tpm2-unseal-age" = {
      description = "TPM2: auto-seal + unseal the cluster age key at boot";
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
        source_key="${cfg.primaryKeyPath}"

        do_seal() {
          echo "tpm2-unseal-age: sealing age key to PCRs [${cfg.pcrList}]..."
          workdir=$(mktemp -d)
          trap 'rm -rf "$workdir"' EXIT

          tpm2_createprimary -C e -c "$workdir/primary.ctx"
          tpm2_startauthsession --policy-session -S "$workdir/policy"
          tpm2_policypcrs $pcr_arg -S "$workdir/policy"
          tpm2_policygetdigest -S "$workdir/policy" -o "$workdir/policy_digest"

          tpm2_create -C "$workdir/primary.ctx" -G sha256 \
            -u "$workdir/public.blob" -r "$workdir/private.blob" \
            -i "$source_key" -L "$workdir/policy"

          tpm2_load -C "$workdir/primary.ctx" \
            -u "$workdir/public.blob" -r "$workdir/private.blob" \
            -c "$workdir/sealed.ctx" -n "$workdir/name"

          tpm2_evictcontrol -C o -c "$workdir/sealed.ctx" ${persistentHandle}

          mkdir -p ${sealedBlobDir}
          printf "persistent_handle=${persistentHandle}\npmr_policy=pcr:%s\nsealed_at=%s\nauto_sealed=true\n" \
            "$pcrs" "$(date -Iseconds)" > "${sealedBlobDir}/meta"
          echo "tpm2-unseal-age: sealed age key at handle ${persistentHandle}"
          trap - EXIT; rm -rf "$workdir"
        }

        do_evict_stale() {
          local handle=$1
          echo "tpm2-unseal-age: evicting stale handle $handle"
          tpm2_evictcontrol -C o -c "$handle" 2>/dev/null || true
          rm -rf ${sealedBlobDir}
        }

        # Check if tpm2-tools is available and TPM is present
        if ! command -v tpm2_getcap >/dev/null 2>&1; then
          echo "tpm2-unseal-age: tpm2-tools not installed, skipping"
          exit 0
        fi
        if ! tpm2_getcap handles-persistent >/dev/null 2>&1; then
          echo "tpm2-unseal-age: TPM not accessible, skipping"
          exit 0
        fi

        # Check for existing sealed blob at the persistent handle
        existing_handle=$(tpm2_getcap handles-persistent 2>/dev/null | grep "0x81" || true)

        if [ -z "$existing_handle" ]; then
          # No blob found — first boot or blob was evicted
          if [ -f "$source_key" ]; then
            echo "tpm2-unseal-age: first boot — auto-sealing source key"
            do_seal
            existing_handle="${persistentHandle}"
          else
            echo "tpm2-unseal-age: no sealed blob and no source key at $source_key"
            echo "tpm2-unseal-age: SecretSpec will use the static key fallback"
            exit 0
          fi
        fi

        # Attempt unseal
        if tpm2_unseal -c "$existing_handle" > ${runtimeKeyPath}.tmp 2>/dev/null; then
          install -D -m 0400 -o root -g root ${runtimeKeyPath}.tmp ${runtimeKeyPath}
          rm -f ${runtimeKeyPath}.tmp
          echo "tpm2-unseal-age: age key unsealed to ${runtimeKeyPath}"
        else
          # Unseal failed — PCRs drifted
          echo "tpm2-unseal-age: unseal failed (PCRs drifted from last seal)"
          rm -f ${runtimeKeyPath}.tmp

          if [ -f "$source_key" ]; then
            echo "tpm2-unseal-age: source key present — auto-resealing to new PCR state"
            do_evict_stale "$existing_handle"
            do_seal
            # Try unseal with freshly-sealed key
            if tpm2_unseal -c ${persistentHandle} > ${runtimeKeyPath}.tmp 2>/dev/null; then
              install -D -m 0400 -o root -g root ${runtimeKeyPath}.tmp ${runtimeKeyPath}
              rm -f ${runtimeKeyPath}.tmp
              echo "tpm2-unseal-age: re-sealed and unsealed to ${runtimeKeyPath}"
            else
              echo "tpm2-unseal-age: re-seal succeeded but unseal still failed"
              echo "tpm2-unseal-age: SecretSpec will use the static key fallback"
              rm -f ${runtimeKeyPath}.tmp
              exit 0
            fi
          else
            echo "tpm2-unseal-age: no source key available for re-seal"
            echo "tpm2-unseal-age: SecretSpec will use the static key fallback"
            exit 0
          fi
        fi
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
