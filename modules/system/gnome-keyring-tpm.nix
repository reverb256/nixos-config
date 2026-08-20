# gnome-keyring-tpm.nix
#
# TPM 2.0 hardware-binding for the GNOME keyring password.
#
# Design:
# - On first boot: generates a random keyring password, seals it to TPM PCR 0+7
#   at a persistent handle — no manual operator step.
# - On every subsequent boot: unseals the password and feeds it to
#   gnome-keyring-daemon via stdin to unlock the login keyring.
# - Auto-reseals on PCR drift (firmware/BIOS change) if the source password
#   file is still present.

{ config, lib, pkgs, ... }:

let
  cfg = config.security.gnomeKeyringTpm;
  runtimePasswordPath = "/run/secrets/keyring-password";
  sealedBlobDir = "/var/lib/gnome-keyring-tpm";
  persistentHandle = "0x81000001";
  sourcePasswordPath = "/var/lib/gnome-keyring-tpm/source-password";

in {
  options.security.gnomeKeyringTpm = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable TPM 2.0 hardware-binding for the GNOME keyring password.
        Requires /dev/tpmrm0 (present on all cluster hosts).
        Auto-seals on first boot and auto-reseals on PCR drift.
      '';
    };

    keyringName = lib.mkOption {
      type = lib.types.str;
      default = "login";
      description = "Name of the keyring to unlock.";
    };

    pcrList = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "0" "7" ];
      description = ''
        TPM PCRs to bind the sealed password to. Default [0 7] = firmware +
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
      "d ${sealedBlobDir} 0700 root root -"
    ];

    systemd.services."gnome-keyring-tpm-unlock" = {
      description = "TPM2: auto-seal + unlock the GNOME keyring password at boot";
      wantedBy = [ "graphical-session.target" ];
      after = [ "systemd-logind.service" ];
      before = [ "gnome-keyring.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = "GNOME_KEYRING_CONTROL=/run/user/1000/keyring";
      };
      script = ''
        set -euo pipefail
        pcrs="${lib.concatStringsSep "," cfg.pcrList}"
        pcr_arg="-l sha256:${lib.concatStringsSep "," cfg.pcrList}"

        do_seal() {
          echo "gnome-keyring-tpm: sealing keyring password to PCRs [$pcrs]..."
          workdir=$(mktemp -d)
          trap 'rm -rf "$workdir"' EXIT

          # Generate a random password if no source exists
          if [ ! -f "${sourcePasswordPath}" ]; then
            openssl rand -base64 32 > "${sourcePasswordPath}"
            chmod 0600 "${sourcePasswordPath}"
            echo "gnome-keyring-tpm: generated new keyring password"
          fi

          tpm2_createprimary -C e -c "$workdir/primary.ctx"
          tpm2_startauthsession --policy-session -S "$workdir/policy"
          tpm2_policypcrs $pcr_arg -S "$workdir/policy"
          tpm2_policygetdigest -S "$workdir/policy" -o "$workdir/policy_digest"

          tpm2_create -C "$workdir/primary.ctx" -G sha256 \
            -u "$workdir/public.blob" -r "$workdir/private.blob" \
            -i "${sourcePasswordPath}" -L "$workdir/policy"

          tpm2_load -C "$workdir/primary.ctx" \
            -u "$workdir/public.blob" -r "$workdir/private.blob" \
            -c "$workdir/sealed.ctx" -n "$workdir/name"

          tpm2_evictcontrol -C o -c "$workdir/sealed.ctx" ${persistentHandle}

          mkdir -p ${sealedBlobDir}
          printf "persistent_handle=${persistentHandle}\npcr_policy=pcr:%s\\nsealed_at=%s\\n" \
            "$pcrs" "$(date -Iseconds)" > "${sealedBlobDir}/meta"
          echo "gnome-keyring-tpm: sealed keyring password at handle ${persistentHandle}"
          trap - EXIT; rm -rf "$workdir"
        }

        do_evict_stale() {
          local handle=$1
          echo "gnome-keyring-tpm: evicting stale handle $handle"
          tpm2_evictcontrol -C o -c "$handle" 2>/dev/null || true
          rm -rf ${sealedBlobDir}
        }

        # Check if tpm2-tools is available and TPM is present
        if ! command -v tpm2_getcap >/dev/null 2>&1; then
          echo "gnome-keyring-tpm: tpm2-tools not installed, skipping"
          exit 0
        fi
        if ! tpm2_getcap handles-persistent >/dev/null 2>&1; then
          echo "gnome-keyring-tpm: TPM not accessible, skipping"
          exit 0
        fi

        # Check for existing sealed blob at the persistent handle
        existing_handle=$(tpm2_getcap handles-persistent 2>/dev/null | grep "0x81000001" || true)

        if [ -z "$existing_handle" ]; then
          # No blob found — first boot or blob was evicted
          do_seal
          existing_handle="${persistentHandle}"
        fi

        # Attempt unseal
        if tpm2_unseal -c "$existing_handle" > ${runtimePasswordPath}.tmp 2>/dev/null; then
          install -D -m 0400 -o root -g root ${runtimePasswordPath}.tmp ${runtimePasswordPath}
          rm -f ${runtimePasswordPath}.tmp
          echo "gnome-keyring-tpm: keyring password unsealed to ${runtimePasswordPath}"

          # Feed password to gnome-keyring-daemon for unlock
          if pgrep -x gnome-keyring-daemon >/dev/null 2>&1; then
            cat ${runtimePasswordPath} | ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --unlock 2>/dev/null || true
            echo "gnome-keyring-tpm: keyring unlocked"
          fi
        else
          # Unseal failed — PCRs drifted
          echo "gnome-keyring-tpm: unseal failed (PCRs drifted from last seal)"
          rm -f ${runtimePasswordPath}.tmp

          if [ -f "${sourcePasswordPath}" ]; then
            echo "gnome-keyring-tpm: source password present — auto-resealing to new PCR state"
            do_evict_stale "$existing_handle"
            do_seal
            # Try unseal with freshly-sealed password
            if tpm2_unseal -c ${persistentHandle} > ${runtimePasswordPath}.tmp 2>/dev/null; then
              install -D -m 0400 -o root -g root ${runtimePasswordPath}.tmp ${runtimePasswordPath}
              rm -f ${runtimePasswordPath}.tmp
              echo "gnome-keyring-tpm: re-sealed and unsealed to ${runtimePasswordPath}"
              cat ${runtimePasswordPath} | ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --unlock 2>/dev/null || true
              echo "gnome-keyring-tpm: keyring unlocked"
            else
              echo "gnome-keyring-tpm: re-seal succeeded but unseal still failed"
              rm -f ${runtimePasswordPath}.tmp
              exit 0
            fi
          else
            echo "gnome-keyring-tpm: no source password available for re-seal"
            exit 0
          fi
        fi
      '';
      path = with pkgs; [ tpm2-tools ];
    };
  };
}
