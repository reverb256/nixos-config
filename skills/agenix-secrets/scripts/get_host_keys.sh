#!/usr/bin/env bash
# Get SSH host public keys and convert them to age format
# This script helps you set up host keys for automatic decryption

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================"
echo "Host Key Collection Script"
echo "================================"
echo ""
echo "This script will help you collect age-formatted host keys"
echo "from your NixOS hosts for automatic secret decryption."
echo ""

# Check if ssh-to-age is available locally
if command -v ssh-to-age &> /dev/null; then
    echo "✓ ssh-to-age is available locally"
    USE_LOCAL_SSH_TO_AGE=true
else
    echo "⚠ ssh-to-age not found locally"
    echo "  Script will use remote ssh-to-age via SSH"
    USE_LOCAL_SSH_TO_AGE=false
fi

echo ""
echo "Detected hosts from /etc/nixos/hosts:"
for host_dir in /etc/nixos/hosts/*/; do
    hostname=$(basename "$host_dir")
    echo "  - $hostname"
done

echo ""
read -p "Enter hostname to get key from (or 'all' for all hosts): " HOSTNAME

if [ "$HOSTNAME" = "all" ]; then
    HOSTS=()
    for host_dir in /etc/nixos/hosts/*/; do
        hostname=$(basename "$host_dir")
        HOSTS+=("$hostname")
    done
else
    HOSTS=("$HOSTNAME")
fi

echo ""
echo "================================"
echo "Collecting Host Keys"
echo "================================"
echo ""

for HOST in "${HOSTS[@]}"; do
    echo -e "${GREEN}Getting key for: $HOST${NC}"

    # Try to get the key
    if [ "$USE_LOCAL_SSH_TO_AGE" = true ]; then
        # Use local ssh-to-age with remote SSH
        KEY=$(ssh "$HOST" "cat /etc/ssh/ssh_host_ed25519_key.pub" 2>/dev/null | ssh-to-age 2>/dev/null || echo "")
    else
        # Use remote ssh-to-age via nix-shell
        KEY=$(ssh "$HOST" "nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'" 2>/dev/null || echo "")
    fi

    if [ -z "$KEY" ]; then
        echo -e "${RED}✗ Failed to get key for $HOST${NC}"
        echo "  Try manually:"
        echo "  ssh $HOST 'sudo cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'"
        echo ""
        continue
    fi

    # Validate the key format
    if [[ ! $KEY =~ ^age1 ]]; then
        echo -e "${RED}✗ Invalid key format for $HOST${NC}"
        echo "  Key: $KEY"
        echo ""
        continue
    fi

    echo -e "${GREEN}✓ $HOST:${NC} $KEY"
    echo ""

    # Save to a temp file for easy copy-paste
    echo "$HOST=$KEY" >> /tmp/agenix-host-keys.txt
done

echo ""
echo "================================"
echo "Summary"
echo "================================"
echo ""

if [ -f /tmp/agenix-host-keys.txt ]; then
    echo "Host keys saved to: /tmp/agenix-host-keys.txt"
    echo ""
    echo "Next steps:"
    echo "1. Review the collected keys:"
    echo "   cat /tmp/agenix-host-keys.txt"
    echo ""
    echo "2. Add them to secrets.nix hosts section:"
    echo "   hosts = {"
    while IFS='=' read -r host key; do
        echo "    $host = \"$key\";"
    done < /tmp/agenix-host-keys.txt
    echo "  };"
    echo ""
    echo "3. Re-encrypt secrets with host keys:"
    echo "   RULES=/etc/nixos/secrets.nix agenix -r -i ~/.age/key.txt"
    echo ""
    echo "4. Update each secret's publicKeys to include hosts.<hostname>"
    echo ""
else
    echo "No keys were collected successfully."
    echo ""
    echo "Manual method:"
    echo "For each host, run:"
    echo "  ssh <hostname> 'sudo cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'"
fi
