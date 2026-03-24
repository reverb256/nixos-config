# SSH Certificate Authority Module for Single Sign-On
# Provides SSH certificate-based authentication for cluster-wide SSO
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types mkIf;

  # SSH CA public key for verifying certificates
  # The private key should be stored securely and used to sign certificates
  # Generate with: ssh-keygen -t ed25519 -f ~/.ssh/ca_key -C "cluster-CA"
  caPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIINREWq2TwFSGaDxTBDv7xaFGw7fniE10i91sn6Xqhkg cluster-CA@zephyr";
  # Certificate principals (usernames) authorized by the CA
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
      default = "52w"; # 1 year
      description = "SSH certificate validity period (e.g., 52w for 1 year, 24h for 1 day)";
    };
  };

  config = mkIf config.services.ssh-ca.enable {
    # ============================================================================
    # TRUSTED USER CA KEYS - Trust certificates signed by our CA
    # ============================================================================
    # This tells sshd to trust any user certificate signed by our CA
    services.openssh.extraConfig = ''
      # Trusted User CA Keys - Accept certificates signed by our CA
      TrustedUserCAKeys ${pkgs.writeText "ssh-ca.pub" caPublicKey}

      # AuthorizedPrincipalsFile - Map certificate principals to users
      AuthorizedPrincipalsFile ${pkgs.writeText "authorized_principals" ''
        j_kro
      ''}

      # Require certificates for enhanced security (optional - set to false for key fallback)
      # AuthenticationMethods publickey
    '';

    # ============================================================================
    # CERTIFICATE GENERATION HELPER SCRIPT
    # ============================================================================
    # Script to generate and sign SSH certificates for cluster users
    environment.systemPackages = with pkgs; [
      (writeScriptBin "ssh-sign-cert" ''
        #!/bin/env bash
        # SSH Certificate Signing Script for Cluster SSO
        # Usage: ssh-sign-cert [identity_file] [principals] [validity]

        set -euo pipefail

        IDENTITY_FILE="''${1:-$HOME/.ssh/id_ed25519}"
        PRINCIPALS="''${2:-j_kro}"
        VALIDITY="''${3:-52w}"
        CA_KEY="''${SSH_CA_KEY:-/etc/ssh/ca_key}"
        CERT_DIR="''${CERT_DIR:-$HOME/.ssh}"

        echo "[SSH CA] Generating SSH certificate..."

        # Check if CA key exists
        if [[ ! -f "$CA_KEY" ]]; then
          echo "[SSH CA] ERROR: CA private key not found at $CA_KEY"
          echo "[SSH CA] Generate one with: ssh-keygen -t ed25519 -f $CA_KEY -C 'cluster-CA'"
          exit 1
        fi

        # Check if public key exists
        if [[ ! -f "$IDENTITY_FILE.pub" ]]; then
          echo "[SSH CA] ERROR: Public key not found: $IDENTITY_FILE.pub"
          exit 1
        fi

        # Sign the public key
        ssh-keygen -s "$CA_KEY" \
          -I "$PRINCIPALS@cluster" \
          -n "$PRINCIPALS" \
          -V "$VALIDITY" \
          -z "$$(date +%s)" \
          "$IDENTITY_FILE.pub"

        # Set proper permissions
        chmod 600 "$IDENTITY_FILE-cert.pub"

        echo "[SSH CA] ✓ Certificate generated: $IDENTITY_FILE-cert.pub"
        echo "[SSH CA]   Principal: $PRINCIPALS"
        echo "[SSH CA]   Valid for: $VALIDITY"
        echo "[SSH CA]   Valid from: $$(ssh-keygen -L -f "$IDENTITY_FILE-cert.pub" | grep 'Valid:' | awk '{print $2}')"
        echo "[SSH CA]   Valid to:   $$(ssh-keygen -L -f "$IDENTITY_FILE-cert.pub" | grep 'Valid:' | awk '{print $4}')"
      '')

      (writeScriptBin "ssh-cert-info" ''
        #!/bin/env bash
        # Display SSH certificate information
        # Usage: ssh-cert-info [cert_file]

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
        # Generate a new SSH CA key pair
        # Usage: ssh-ca-generate [output_path]

        CA_KEY_PATH="''${1:-/etc/ssh/ca_key}"

        echo "[SSH CA] Generating new SSH CA key pair..."
        ssh-keygen -t ed25519 -f "$CA_KEY_PATH" -C "cluster-CA@zephyr"

        # Set proper permissions
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

    # ============================================================================
    # CERTIFICATE REFRESH SERVICE (Optional)
    # ============================================================================
    # Automatically refresh certificates before they expire
    # Only enabled if autoSign is true and CA key is available
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
