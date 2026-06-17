#!/usr/bin/env bash
# Sign an SSH key with the cluster CA (backup key)
# The YubiKey PIV slot 9c holds the authoritative copy
# Usage: ssh-sign-cert [identity_key] [principal] [validity]
set -euo pipefail

IDENTITY="${1:-$HOME/.ssh/id_ed25519}"
PRINCIPAL="${2:-j_kro}"
VALIDITY="${3:-52w}"
CA_KEY="/etc/ssh/ca_key"

if [ ! -f "$CA_KEY" ]; then
  echo "ERROR: CA key not found at $CA_KEY"
  echo "Decrypt from: /etc/nixos/secrets/infra/yubikey-ca-key-backup.age"
  exit 1
fi

if [ ! -f "$IDENTITY.pub" ]; then
  echo "ERROR: Public key not found: $IDENTITY.pub"
  exit 1
fi

ssh-keygen -s "$CA_KEY" \
  -I "$PRINCIPAL@cluster" \
  -n "$PRINCIPAL" \
  -V "+$VALIDITY" \
  -z "$(date +%s)" \
  "$IDENTITY.pub"

echo "Certificate: $IDENTITY-cert.pub"
echo "  Principal: $PRINCIPAL"
echo "  Valid for: $VALIDITY"
