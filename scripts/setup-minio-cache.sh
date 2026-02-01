#!/usr/bin/env bash
set -e

MINIO_ENDPOINT="${1:-http://localhost:9000}"
BUCKET_NAME="${2:-nix-cache}"

echo "=== MinIO Nix Cache Setup ==="
echo "Endpoint: $MINIO_ENDPOINT"
echo "Bucket: $BUCKET_NAME"
echo ""

if ! command -v mc &> /dev/null; then
    echo "Installing MinIO client (mc)..."
    nix-shell -p minio-client --run "echo 'mc installed'"
fi

echo "Configuring MinIO alias..."
mc alias set nixcache "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY"

echo "Creating bucket: $BUCKET_NAME"
mc mb -p "nixcache/$BUCKET_NAME"

echo "Setting bucket policy..."
cat > /tmp/bucket-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {"AWS": ["*"]},
            "Action": ["s3:GetObject"],
            "Resource": ["arn:aws:s3:::nix-cache/*"]
        }
    ]
}
EOF
mc policy set-json /tmp/bucket-policy.json "nixcache/$BUCKET_NAME"

read -p "Generate signing keys for cache? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Generating signing keys..."
    mkdir -p /etc/nix
    
    nix key generate-secret --key-name "$BUCKET_NAME" > /etc/nix/cache-priv-key.pem
    nix key convert-secret-to-public < /etc/nix/cache-priv-key.pem > /etc/nix/cache-pub-key.pem
    
    echo "Private key: /etc/nix/cache-priv-key.pem"
    echo "Public key: /etc/nix/cache-pub-key.pem"
    echo ""
    echo "Add this public key to your NixOS config:"
    cat /etc/nix/cache-pub-key.pem
fi

echo ""
echo "=== Setup Complete ==="
echo "Add to your NixOS configuration:"
echo ""
echo "services.nixos-minio-cache = {"
echo "  enable = true;"
echo "  endpoint = \"$MINIO_ENDPOINT\";"
echo "  bucket = \"$BUCKET_NAME\";"
echo "  credentialsFile = /run/agenix/minio-credentials;"
echo "  publicKey = \"$(cat /etc/nix/cache-pub-key.pem 2>/dev/null || echo 'your-public-key-here')\";"
echo "  privateKeyFile = /etc/nix/cache-priv-key.pem;"
echo "};"
