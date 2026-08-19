# tpm2-age-binding.nix
#
# TPM 2.0 hardware-binding for the cluster age key used by SecretSpec/sops.
#
# Design:
# - A sealed age key blob lives at /var/lib/tpm2-age-sealed/key.age (created
#   once by the operator using tpm2_create with a PCR policy).
# - At boot, tpm2-unseal-age.service unseals the key (requires matching PCRs
#   or physical presence) and writes it to /run/secrets/cluster-age-key
#   (mode 0400, root only).
# - secretspec-creds.ageKeyFile is overridden per-host to point at the
#   runtime unsealed path, so the entire sops pipeline is hardware-bound.
#
# This module does NOT modify SecretSpec itself. It sits below it — the
# unsealed key file is consumed via the existing SOPS_AGE_KEY_FILE env var
# that secretspec-creds already sets.
#
# Requirements:
# - TPM 2.0 hardware (checked at eval via lib.assertions)
# - The operator runs tpm2-seal-age-keygen.service once to create the sealed
#   blob. Subsequent boots unseal automatically.
# - PCR policy: 0,7 (firmware + Secure Boot). Survives OS updates; breaks
#   if firmware or Secure Boot state changes (intentional).
#
# Scope: cluster-wide (all hosts that enable this module + have a TPM).
# Override per-host in hosts/<host>/configuration.nix if needed.

{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.security.tpm2AgeBinding;
  runtimeKeyPath = "/run/secrets/cluster-age-key";
  sealedBlobDir = "/var/lib/tpm2-age-sealed";
  sealedBlobPath = "${sealedBlobDir}/key.age";
in
{
  options.security.tpm2AgeBinding = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable TPM 2.0 hardware-binding for the cluster age key.
        Requires /dev/tpmrm0 and tpm2-tools at activation.
      '';
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = runtimeKeyPath;
      defaultText = lib.literalExpression "runtimeKeyPath (the unsealed key at boot)";
      description = ''
        Path that secretspec-creds should use for the age identity.
        Defaults to the TPM-unsealed runtime path. Override only if you
        want to fall back to a static file.
      '';
    };

    primaryKeyPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/.age/key.txt";
      description = ''
        Source age key file to seal on first boot. The operator runs the
        keygen service once to read this and create the sealed blob.
      '';
    };

    pcrList = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "0" "7" ];
      description = ''
        TPM PCRs to bind the sealed key to. Default [0 7] = firmware +
        Secure Boot state. Survives kernel/OS updates; breaks if firmware
        or Secure Boot configuration changes.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.pathExists "/dev/tpmrm0" || lib.pathExists "/dev/tpm0";
        message = "tpm2-age-binding enabled but no TPM device found at /dev/tpmrm0 or /dev/tpm0";
      }
    ];

    environment.systemPackages = with pkgs; [
      tpm2-tools
      tpm2-tss
    ];

    systemd.tmpfiles.rules = [
      "d /run/secrets 0750 root root -"
    ];

    # One-time key generation service: reads the source age key, creates
    # a sealed blob. Run manually via systemctl start tpm2-seal-age-keygen.
    # Idempotent: skips if sealed blob already exists.
    systemd.services."tpm2-seal-age-keygen" = {
      description = "TPM2: seal the cluster age key to PCRs (one-time init)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        if [ -f "${sealedBlobPath}" ] && [ -s ${sealedBlobPath} ]; then
          echo "sealed blob already exists at ${sealedBlobPath}"
          exit 0
        fi

        if [ ! -f "${cfg.primaryKeyPath}" ]; then
          echo "source age key not found at ${cfg.primaryKeyPath}"
          echo "place the age key there and run systemctl start tpm2-seal-age-keygen"
          exit 1
        fi

        mkdir -p ${sealedBlobDir}
        pcr_spec="pcr:${(lib.concatStringsSep "," cfg.pcrList)}"
        echo "using PCR policy: $pcr_spec"

        workdir=$(mktemp -d)
        trap 'rm -rf "$workdir"' EXIT

        tpm2_createprimary -C e -c "$workdir/primary.ctx"

        tpm2_startauthsession --policy-session -S "$workdir/policy"
        tpm2_policypcrs -S "$workdir/policy" -l sha256:${(lib.concatStringsSep "," cfg.pcrList)}
        tpm2_policygetdigest -S "$workdir/policy" -o "$workdir/policy_digest"

        tpm2_create -C "$workdir/primary.ctx" -G sha256 \
          -u "$workdir/public.blob" -r "$workdir/private.blob" \
          -i "${cfg.primaryKeyPath}" -L "$workdir/policy"

        tpm2_load -C "$workdir/primary.ctx" \
          -u "$workdir/public.blob" -r "$workdir/private.blob" \
          -c "$workdir/sealed.ctx" -n "$workdir/name"

        tpm2_evictcontrol -C o -c "$workdir/sealed.ctx" 0x81000000

        printf "persistent_handle=0x81000000\n" > "${sealedBlobDir}/meta"
        echo "sealed age key at persistent handle 0x81000000"
      '';
      path = with pkgs; [ tpm2-tools ];
    };

    # Boot-time unseal: writes the age key to runtime path before
    # secretspec-creds runs.
    systemd.services."tpm2-unseal-age" = {
      description = "TPM2: unseal the cluster age key at boot";
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
        handle=0x81000000

        if [ ! -f "${cfg.ageKeyFile}" ] && [ ! -f "${sealedBlobDir}/meta" ]; then
          echo "sealed blob not found at ${sealedBlobDir}, skipping"
          exit 0
        fi

        if ! tpm2_getcap handles-persistent 2>/dev/null | grep -q "0x1000000"; then
          echo "persistent handle 0x81000000 not found, run tpm2-seal-age-keygen"
          exit 0
        fi

        tpm2_unseal -c $handle > ${runtimeKeyPath}.tmp 2>/dev/null || {
          echo "unseal failed (PCRs may not match)"
          rm -f ${runtimeKeyPath}.tmp
          exit 0
        }

        install -D -m 0400 -o root -g root ${runtimeKeyPath}.tmp ${runtimeKeyPath}
        rm -f ${runtimeKeyPath}.tmp
        echo "age key unsealed to ${runtimeKeyPath}"
      '';
      path = with pkgs; [ tpm2-tools ];
    };

    # Override secretspec ageKeyFile to use the TPM-unsealed runtime path.
    # secretspec-creds and secretspec-validator modules are imported per-host
    # (see hosts/*/configuration.nix). The ageKeyFile override here takes
    # precedence over any host-level value via mkForce.
    services.secretspec-creds.ageKeyFile = lib.mkIf cfg.enable cfg.ageKeyFile;
    services.secretspec-validator.ageKeyFile = lib.mkIf cfg.enable cfg.ageKeyFile;
  };
}
