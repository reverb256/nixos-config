{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types mkIf;

  caPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIINREWq2TwFSGaDxTBDv7xaFGw7fniE10i91sn6Xqhkg cluster-CA@zephyr";
in {
  options.services.ssh-ca = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable SSH certificate authority for SSO";
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
      TrustedUserCAKeys ${pkgs.writeText "ssh-ca.pub" caPublicKey}

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
