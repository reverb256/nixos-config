#!/usr/bin/env bash
# Generate secure credentials for AIStor (MinIO)
# Creates random passwords for demo/testing or provides setup instructions

set -e

echo "=== AIStor Credentials Generator ==="
echo ""

# Function to generate secure random password
generate_password() {
    local length=${1:-24}
    # Generate secure random password using /dev/urandom
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
}

# Function to generate AWS-compatible access key
generate_access_key() {
    # MinIO access keys are typically alphanumeric, 20 characters
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20
}

echo "Choose option:"
echo "1) Generate secure random credentials (recommended for production)"
echo "2) Use demo credentials (minioadmin/minioadmin)"
echo "3) Set custom credentials interactively"
echo ""
read -p "Enter choice (1-3): " choice

case $choice in
    1)
        echo ""
        echo "--- Generating Secure Random Credentials ---"
        
        ACCESS_KEY=$(generate_access_key)
        SECRET_KEY=$(generate_password 32)
        
        echo "Generated credentials:"
        echo "  Access Key:  $ACCESS_KEY"
        echo "  Secret Key:  $SECRET_KEY"
        echo ""
        
        # Save to temporary file
        CRED_FILE="/tmp/minio-cache-credentials-$(date +%Y%m%d-%H%M%S)"
        cat > "$CRED_FILE" << EOF
MINIO_ACCESS_KEY=$ACCESS_KEY
MINIO_SECRET_KEY=$SECRET_KEY
EOF
        
        echo "✓ Credentials saved to: $CRED_FILE"
        echo ""
        echo "To encrypt for NixOS:"
        echo "  cat '$CRED_FILE' | grep -v '^#'"
        echo ""
        ;;
    2)
        echo ""
        echo "--- Using Demo Credentials ---"
        echo "⚠ WARNING: These are NOT secure for production!"
        echo ""
        
        ACCESS_KEY="minioadmin"
        SECRET_KEY="minioadmin"
        
        echo "Demo credentials:"
        echo "  Access Key:  $ACCESS_KEY"
        echo "  Secret Key:  $SECRET_KEY"
        echo ""
        
        # Save to temporary file
        CRED_FILE="/tmp/minio-cache-credentials-demo"
        cat > "$CRED_FILE" << EOF
MINIO_ACCESS_KEY=$ACCESS_KEY
MINIO_SECRET_KEY=$SECRET_KEY
EOF
        
        echo "✓ Credentials saved to: $CRED_FILE"
        echo ""
        echo "To encrypt for NixOS:"
        echo "  cat '$CRED_FILE' | grep -v '^#'"
        echo ""
        ;;
    3)
        echo ""
        echo "--- Interactive Credential Setup ---"
        echo ""
        
        read -p "MinIO Access Key (default: minioadmin): " ACCESS_KEY
        ACCESS_KEY=${ACCESS_KEY:-minioadmin}
        
        read -s -p "MinIO Secret Key (leave blank to auto-generate): " SECRET_KEY
        echo ""
        
        if [ -z "$SECRET_KEY" ]; then
            SECRET_KEY=$(generate_password 32)
            echo "Auto-generated secret key (32 characters)"
        fi
        
        echo ""
        echo "Credentials:"
        echo "  Access Key:  $ACCESS_KEY"
        echo "  Secret Key:  $(echo "$SECRET_KEY" | sed 's/./*/****/')"
        echo ""
        
        # Save to temporary file
        CRED_FILE="/tmp/minio-cache-credentials-custom"
        cat > "$CRED_FILE" << EOF
MINIO_ACCESS_KEY=$ACCESS_KEY
MINIO_SECRET_KEY=$SECRET_KEY
EOF
        
        echo "✓ Credentials saved to: $CRED_FILE"
        echo ""
        echo "To encrypt for NixOS:"
        echo "  cat '$CRED_FILE' | grep -v '^#'"
        echo ""
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

# Encryption instructions
echo "=== Encryption Instructions ==="
echo ""
echo "1. Ensure you have age and agenix installed:"
echo "   nix-shell -p age agenix"
echo ""
echo "2. Encrypt for all 4 cluster hosts (zephyr, nexus, forge, sentry):"
echo "   cd /etc/nixos"
echo "   age -r age175jstqazl7sj20xzuhc4l9qn0xt0ag0nvh2paxkk6veav95se4ysjua4e5 \\"
echo "       -r age19r77h4d3d93fla0ptc4zu3yvdxhvykdusd23c5wmrmzut55rn96qk0kc3n \\"
echo "       -r age1chus24x5vg85993trehnms4gndw9e7qm0m3z5q65997c8az7rf6svffh4w \\"
echo "       -r age14duc9p3yrmelfjd94tfkzgenpfcfarucn3ax6ygl0w4erh9p0ddqr674ly \\"
echo "       -o secrets/minio-cache-credentials.age \\"
echo "       '$CRED_FILE'"
echo ""
echo "3. Clean up plaintext file:"
echo "   shred -u '$CRED_FILE'"
echo ""

# Setup MinIO root password on nexus
echo "=== MinIO Server Setup (nexus) ==="
echo ""
echo "The AIStor server on nexus also needs root credentials."
echo "These are the SAME as the cache credentials above."
echo ""
echo "On nexus (10.1.1.120):"
echo "  ssh nexus"
echo "  sudo mkdir -p /etc/minio"
echo "  sudo sh -c 'cat > /etc/minio/minio-root.env << EOFPASS'"
echo "  MINIO_ROOT_USER=$ACCESS_KEY"
echo "  MINIO_ROOT_PASSWORD=$SECRET_KEY"
echo "  EOFPASS'"
echo ""
echo "Then deploy: just deploy-nexus"
echo ""

# Post-encryption steps
echo "=== After Encryption ==="
echo ""
echo "1. Uncomment the secret in secrets files:"
echo "   Edit secrets/secrets.nix: uncomment minio-cache-credentials line"
echo "   Edit secrets/age-secrets.nix: uncomment minio-cache-credentials lines"
echo ""
echo "2. Uncomment the credential file in zephyr config:"
echo "   Edit hosts/zephyr/configuration.nix: uncomment credentialsFile line"
echo ""
echo "3. Deploy to enable cache:"
echo "   just deploy-zephyr"
echo ""
echo "4. Verify cache is working:"
echo "   nix store ping --store http://10.1.1.120:9000/nix-cache"
echo ""

echo "=== Security Notes ==="
echo ""
echo "- Store these credentials securely (password manager, etc.)"
echo "- Never commit plaintext credentials to git"
echo "- Rotate credentials periodically (monthly recommended)"
echo "- Use strong, unique passwords for production"
echo ""

# Save credentials summary to a file
SUMMARY_FILE="/tmp/aistor-credentials-summary.txt"
cat > "$SUMMARY_FILE" << EOF
AIStor Credentials Summary
Generated: $(date)

Server: nexus (10.1.1.120:9000)
Console: http://10.1.1.120:9001

Credentials:
  Access Key: $ACCESS_KEY
  Secret Key: $SECRET_KEY

Files to update after encryption:
  1. secrets/secrets.nix - uncomment minio-cache-credentials
  2. secrets/age-secrets.nix - uncomment minio-cache-credentials block
  3. hosts/zephyr/configuration.nix - uncomment credentialsFile line

MinIO server setup (on nexus):
  ssh nexus
  sudo mkdir -p /etc/minio
  sudo sh -c 'cat > /etc/minio/minio-root.env << EOF'
  MINIO_ROOT_USER=$ACCESS_KEY
  MINIO_ROOT_PASSWORD=$SECRET_KEY
  EOF'

Encrypted file location:
  /etc/nixos/secrets/minio-cache-credentials.age

Backup this summary file securely!
EOF

echo "✓ Summary saved to: $SUMMARY_FILE"
echo ""
echo "For reference, save this file with your credentials securely."
