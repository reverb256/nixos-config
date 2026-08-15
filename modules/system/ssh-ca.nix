{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types mkIf;

  # File-based ed25519 CA (backup, at /etc/ssh/ca_key)
  caPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIINREWq2TwFSGaDxTBDv7xaFGw7fniE10i91sn6Xqhkg cluster-CA@zephyr";

  # Hardware CA in YubiKey PIV slot 9c (primary, requires touch)
  # Backed up encrypted at secrets/infra/yubikey-ca-key-backup.age
  yubikeyCaPublicKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEa3NkzrDIEecwgki4V5pSGaH3cgqhSJIw9+KRsKDwmmIQyZORa7vwul6BT7j57lsw6UeQWhlb9+m3N+phe8ml4=";

  # Cluster SSH CA (2026-08-14, sops key at secrets/infra/cluster-ssh-ca-key.yaml,
  # pub committed at certs/cluster-ssh-ca.pub). Signs the site-agency deploy
  # identity (principals j_kro,runner-siteagency). Added here so all cluster
  # CAs live in ONE TrustedUserCAKeys list (was a duplicate in ssh.nix).
  clusterCaPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF2gn846NCojtn2x1Q0LLpHl";

  # Canonical host table for signing host-cert principals (mirrors ssh.nix).
  # Certs must list every name a host is reached by (hostname, .lan, IP,
  # tailscale) or clients connecting via the alternate name will reject it.
  hosts = {
    zephyr = {
      ip = "10.1.1.110";
      tailscale = "100.81.182.5";
    };
    nexus = {
      ip = "10.1.1.120";
      tailscale = "100.86.158.18";
    };
    forge = {
      ip = "10.1.1.130";
      tailscale = "100.95.222.45";
    };
    sentry = {
      ip = "10.1.1.140";
      tailscale = "100.82.210.39";
    };
  };

  hostName = config.networking.hostName;
  myHost =
    hosts.${
      hostName
    } or {
      ip = "";
      tailscale = "";
    };
  # Principals as a comma-separated list: host,host.lan,ip,tailscale
  principals = lib.concatStringsSep "," (lib.filter (s: s != "") [
    hostName
    "${hostName}.lan"
    myHost.ip
    myHost.tailscale
  ]);
  keyId = "${hostName}.cluster.local";

  # Fingerprint of the canonical CA pubkey, used to detect stale certs
  # signed by a previous CA key so they get re-signed on boot.
  # MUST stay in sync with caPublicKey above: if you rotate the CA
  # (secrets/infra/ssh-ca-key.yaml), update BOTH or the stale-CA detection
  # silently stops working and hosts keep serving untrusted certs.
  caFingerprint = "SHA256:G3m+DW7YInI2geXhZ/F+mILUTmkqxuW8bj6TgT5qIe4";
in {
  options.services.ssh-ca = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable SSH certificate authority for SSO";
    };

    signHostKeys = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Declaratively sign the local SSH host key with the cluster CA on
        boot. Re-signs whenever the cert is missing, was signed by a
        different CA, or its principals don't cover the current host
        names — so a rotated host key (e.g. after a reinstall) gets a
        fresh cert automatically instead of triggering known_hosts
        MITM warnings. Requires the CA key at /run/secrets/ssh-ca-key
        (secretspec-creds) or /etc/ssh/ca_key.
      '';
    };

    autoSign = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically sign SSH keys on login (requires CA private key)";
    };

    caKeyPath = mkOption {
      type = types.str;
      default = "/etc/ssh/ca_key";
      description = "Path to SSH CA private key for signing certificates";
    };

    certificateValidity = mkOption {
      type = types.str;
      default = "52w";
      description = "SSH certificate validity period (e.g., 52w for 1 year, 24h for 1 day)";
    };
  };

  config = mkIf config.services.ssh-ca.enable {
    services.openssh.extraConfig = ''
      TrustedUserCAKeys ${pkgs.writeText "ssh-ca.pub" (caPublicKey + "\n" + yubikeyCaPublicKey + "\n" + clusterCaPublicKey)}

      AuthorizedPrincipalsFile ${pkgs.writeText "authorized_principals" ''
        j_kro
      ''}

    '';

    environment.systemPackages = with pkgs; [
      (writeScriptBin "ssh-sign-cert" ''
        #!/bin/env bash

        set -euo pipefail

        IDENTITY_FILE="''${1:-$HOME/.ssh/id_ed25519}"
        PRINCIPALS="''${2:-j_kro}"
        VALIDITY="''${3:-52w}"
        CA_KEY="''${SSH_CA_KEY:-/etc/ssh/ca_key}"
        CERT_DIR="''${CERT_DIR:-$HOME/.ssh}"

        echo "[SSH CA] Generating SSH certificate..."

        if [[ ! -f "$CA_KEY" ]]; then
          echo "[SSH CA] ERROR: CA private key not found at $CA_KEY"
          echo "[SSH CA] Generate one with: ssh-keygen -t ed25519 -f $CA_KEY -C 'cluster-CA'"
          exit 1
        fi

        if [[ ! -f "$IDENTITY_FILE.pub" ]]; then
          echo "[SSH CA] ERROR: Public key not found: $IDENTITY_FILE.pub"
          exit 1
        fi

        ssh-keygen -s "$CA_KEY" \
          -I "$PRINCIPALS@cluster" \
          -n "$PRINCIPALS" \
          -V "$VALIDITY" \
          -z "$$(date +%s)" \
          "$IDENTITY_FILE.pub"

        chmod 600 "$IDENTITY_FILE-cert.pub"

        echo "[SSH CA] ✓ Certificate generated: $IDENTITY_FILE-cert.pub"
        echo "[SSH CA]   Principal: $PRINCIPALS"
        echo "[SSH CA]   Valid for: $VALIDITY"
        echo "[SSH CA]   Valid from: $$(ssh-keygen -L -f "$IDENTITY_FILE-cert.pub" | grep 'Valid:' | awk '{print $2}')"
        echo "[SSH CA]   Valid to:   $$(ssh-keygen -L -f "$IDENTITY_FILE-cert.pub" | grep 'Valid:' | awk '{print $4}')"
      '')

      (writeScriptBin "ssh-cert-info" ''
        #!/bin/env bash

        CERT_FILE="''${1:-$HOME/.ssh/id_ed25519-cert.pub}"

        if [[ ! -f "$CERT_FILE" ]]; then
          echo "[SSH CA] ERROR: Certificate not found: $CERT_FILE"
          exit 1
        fi

        echo "[SSH CA] Certificate Information:"
        echo "────────────────────────────────────"
        ssh-keygen -L -f "$CERT_FILE"
      '')

      (writeScriptBin "ssh-ca-generate" ''
        #!/bin/env bash

        CA_KEY_PATH="''${1:-/etc/ssh/ca_key}"

        echo "[SSH CA] Generating new SSH CA key pair..."
        ssh-keygen -t ed25519 -f "$CA_KEY_PATH" -C "cluster-CA@zephyr"

        chmod 600 "$CA_KEY_PATH"
        chmod 644 "$CA_KEY_PATH.pub"

        echo "[SSH CA] ✓ CA key pair generated:"
        echo "[SSH CA]   Private: $CA_KEY_PATH"
        echo "[SSH CA]   Public:  $CA_KEY_PATH.pub"
        echo ""
        echo "[SSH CA] Add this to your SSH module caPublicKey:"
        echo "[SSH CA] ──────────────────────────────────────"
        cat "$CA_KEY_PATH.pub"
        echo "[SSH CA] ──────────────────────────────────────"
      '')
    ];

    # Declarative host-cert signing: keeps ssh_host_ed25519_key-cert.pub
    # valid and CA-canonical on every boot. Fixes the "host key rotated,
    # known_hosts MITM warning" whack-a-mole at the root: whatever key
    # /etc/ssh holds, it gets re-signed by the cluster CA.
    systemd.services.ssh-host-cert-sign = lib.mkIf config.services.ssh-ca.signHostKeys {
      description = "Sign SSH host key with cluster CA";
      wantedBy = ["multi-user.target"];
      after = ["secretspec-creds.service"];
      wants = ["secretspec-creds.service"];
      # 2026-08-15: without this, the default service PATH lacks openssh and
      # the script's bare `ssh-keygen` fails to resolve -> "no CA key
      # available, skipping" despite a valid key on disk.
      path = [ pkgs.openssh ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        HOST_KEY=/etc/ssh/ssh_host_ed25519_key
        CERT=$HOST_KEY-cert.pub
        KEY_PUB=$HOST_KEY.pub

        [ -f "$KEY_PUB" ] || { echo "ssh-host-cert-sign: no $KEY_PUB, skipping"; exit 0; }

        # Prefer the secretspec-provisioned CA key, fall back to the file CA.
        # Validate each candidate is actually a readable private key — a stale
        # or corrupted leftover (e.g. the old block-scalar artifact) would
        # otherwise pass the -s check and make ssh-keygen fail the unit.
        CA_KEY=""
        for c in /run/secrets/ssh-ca-key ${config.services.ssh-ca.caKeyPath}; do
          if [ -s "$c" ] && ssh-keygen -y -f "$c" >/dev/null 2>&1; then
            CA_KEY="$c"; break
          fi
        done
        if [ -z "$CA_KEY" ]; then
          echo "ssh-host-cert-sign: no CA key available, skipping"
          exit 0
        fi

        NEED_SIGN=false

        if [ ! -f "$CERT" ]; then
          echo "ssh-host-cert-sign: cert missing, signing"
          NEED_SIGN=true
        else
          # Re-sign if the cert was signed by a different CA (key rotated)
          # or the principals don't cover this host's current names.
          if ! ssh-keygen -L -f "$CERT" 2>/dev/null | grep -q "Signing CA: ED25519 ${caFingerprint}"; then
            echo "ssh-host-cert-sign: cert signed by stale CA, re-signing"
            NEED_SIGN=true
          elif ! ssh-keygen -L -f "$CERT" 2>/dev/null | grep -q "${hostName}.lan" || \
            ! ssh-keygen -L -f "$CERT" 2>/dev/null | grep -q "${myHost.ip}"; then
            echo "ssh-host-cert-sign: cert principals stale, re-signing"
            NEED_SIGN=true
          fi
        fi

        if [ "$NEED_SIGN" = false ]; then
          echo "ssh-host-cert-sign: cert valid, nothing to do"
          exit 0
        fi

        rm -f "$CERT"
        ssh-keygen -s "$CA_KEY" \
          -h \
          -I "${keyId}" \
          -n "${principals}" \
          -V "+52w" \
          -z "$(date +%s)" \
          "$KEY_PUB" >/dev/null 2>&1

        chmod 0644 "$CERT"
        chown root:root "$CERT"

        # Restart sshd so the fresh cert is served immediately.
        systemctl try-restart sshd.service 2>/dev/null || true
        echo "ssh-host-cert-sign: signed ${hostName} host cert (${keyId})"
      '';
    };

    systemd.services.ssh-cert-refresh = lib.mkIf config.services.ssh-ca.autoSign {
      description = "SSH Certificate Refresh Service";
      serviceConfig = {
        Type = "oneshot";
        User = "j_kro";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "ssh-cert-refresh" ''
          ssh-sign-cert $HOME/.ssh/id_ed25519 j_kro ${config.services.ssh-ca.certificateValidity}
        '';
      };
    };

    systemd.timers.ssh-cert-refresh = lib.mkIf config.services.ssh-ca.autoSign {
      description = "SSH Certificate Refresh Timer";
      wantedBy = ["timers.target"];
      partOf = ["ssh-cert-refresh.service"];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };
  };
}
