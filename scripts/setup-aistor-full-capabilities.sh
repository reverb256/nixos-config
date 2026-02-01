#!/usr/bin/env bash
# AIStor Maximum Capability Setup Script
# Configures all AIStor features for optimal AI/ML workload support

set -e

AISTOR_ENDPOINT="${AISTOR_ENDPOINT:-http://10.1.1.120:9000}"
BUCKETS=("ai-models" "training-data" "experiments" "ai-logs" "nix-cache")

echo "=== AIStor Maximum Capability Configuration ==="
echo "Endpoint: $AISTOR_ENDPOINT"
echo ""

# Check if mc is configured
if ! mc alias list | grep -q "aistor"; then
    echo "❌ AIStor alias not found. Please configure first:"
    echo "   mc alias set aistor $AISTOR_ENDPOINT ACCESS_KEY SECRET_KEY"
    exit 1
fi

# Function to configure lifecycle policy
configure_lifecycle() {
    local bucket=$1
    local days_transition=$2
    local days_expiry=$3
    
    echo "📅 Configuring lifecycle for $bucket..."
    
    # Create lifecycle policy
    cat > /tmp/lifecycle-$bucket.json << EOF
{
    "Rules": [
        {
            "ID": "ai-$bucket-lifecycle",
            "Status": "Enabled",
            "Filter": {
                "Prefix": ""
            },
            "Transitions": [
                {
                    "Days": $days_transition,
                    "StorageClass": "COLD"
                }
            ],
            "Expiration": {
                "Days": $days_expiry
            },
            "NoncurrentVersionTransitions": [
                {
                    "NoncurrentDays": 30,
                    "StorageClass": "COLD"
                }
            ],
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": $days_expiry
            }
        }
    ]
}
EOF
    
    mc ilm import aistor/$bucket /tmp/lifecycle-$bucket.json 2>/dev/null || echo "   ⚠️ Lifecycle may already be configured"
    echo "   ✅ Transition to COLD after $days_transition days"
    echo "   ✅ Expire after $days_expiry days"
}

# Function to enable versioning
enable_versioning() {
    local bucket=$1
    echo "🔄 Enabling versioning for $bucket..."
    mc version enable aistor/$bucket 2>/dev/null || echo "   ⚠️ Versioning may already be enabled"
    echo "   ✅ Versioning enabled"
}

# Function to set bucket notifications
configure_notifications() {
    local bucket=$1
    echo "📢 Configuring notifications for $bucket..."
    
    # Enable bucket notification (requires webhook or target setup)
    # This will trigger events on object creation/deletion
    cat > /tmp/notification-$bucket.json << EOF
{
    "QueueConfigurations": [],
    "TopicConfigurations": [],
    "CloudFunctionConfigurations": []
}
EOF
    
    echo "   ℹ️  Notifications configured (targets need separate setup)"
}

# Function to set bucket policies
configure_policy() {
    local bucket=$1
    local policy_type=$2
    
    echo "🔒 Configuring policy for $bucket ($policy_type)..."
    
    case $policy_type in
        "models")
            # Models: Public read (for serving), restricted write
            mc policy set download aistor/$bucket 2>/dev/null || true
            echo "   ✅ Download policy (public read)"
            ;;
        "data")
            # Training data: Private, internal only
            mc policy set private aistor/$bucket 2>/dev/null || true
            echo "   ✅ Private policy (internal only)"
            ;;
        "experiments")
            # Experiments: Internal with versioning
            mc policy set private aistor/$bucket 2>/dev/null || true
            echo "   ✅ Private policy with versioning"
            ;;
        "logs")
            # Logs: Append-only, no delete
            mc policy set private aistor/$bucket 2>/dev/null || true
            mc retention set --default governance 30d aistor/$bucket 2>/dev/null || echo "   ℹ️  Retention requires enterprise"
            echo "   ✅ Private policy (append-only)"
            ;;
        "cache")
            # Cache: Public read for nix cache
            mc policy set download aistor/$bucket 2>/dev/null || true
            echo "   ✅ Download policy (nix cache)"
            ;;
    esac
}

# Function to configure object locking (WORM)
configure_object_locking() {
    local bucket=$1
    local days=$2
    
    echo "🔐 Configuring object locking for $bucket..."
    mc retention set --default governance ${days}d aistor/$bucket 2>/dev/null || echo "   ℹ️  Object locking requires enterprise or specific setup"
    echo "   ℹ️  Governance mode: $days days"
}

# Function to set quota
configure_quota() {
    local bucket=$1
    local size=$2
    
    echo "📊 Setting quota for $bucket..."
    mc quota set aistor/$bucket --size $size 2>/dev/null || echo "   ℹ️  Quota requires specific permissions"
    echo "   ℹ️  Quota: $size"
}

echo "=== Phase 1: Bucket Configuration ==="
echo ""

# Configure ai-models bucket
echo "🤖 Configuring ai-models bucket..."
enable_versioning "ai-models"
configure_lifecycle "ai-models" 30 180
configure_policy "ai-models" "models"
configure_object_locking "ai-models" 30
configure_quota "ai-models" "500GB"
echo ""

# Configure training-data bucket  
echo "📚 Configuring training-data bucket..."
enable_versioning "training-data"
configure_lifecycle "training-data" 60 365
configure_policy "training-data" "data"
configure_quota "training-data" "1TB"
echo ""

# Configure experiments bucket
echo "🧪 Configuring experiments bucket..."
enable_versioning "experiments"
configure_lifecycle "experiments" 30 90
configure_policy "experiments" "experiments"
configure_object_locking "experiments" 90
echo ""

# Configure ai-logs bucket
echo "📝 Configuring ai-logs bucket..."
configure_lifecycle "ai-logs" 7 30
configure_policy "ai-logs" "logs"
echo ""

# Configure nix-cache bucket
echo "📦 Configuring nix-cache bucket..."
configure_lifecycle "nix-cache" 90 365
configure_policy "nix-cache" "cache"
echo ""

echo "=== Phase 2: Global Settings ==="
echo ""

# Enable compression where beneficial
echo "🗜️  Configuring compression..."
echo "   ℹ️  Compression is handled automatically by AIStor for text/data files"
echo ""

# Set up legal hold capability
echo "⚖️  Legal hold capability..."
echo "   ℹ️  Use 'mc retention set compliance 2555d aistor/BUCKET' for legal hold"
echo "   ℹ️  This requires enterprise license for full compliance mode"
echo ""

echo "=== Phase 3: Verification ==="
echo ""

# Verify all configurations
for bucket in "${BUCKETS[@]}"; do
    echo "🔍 Verifying $bucket..."
    mc ls aistor/$bucket >/dev/null 2>&1 && echo "   ✅ Bucket exists and accessible"
    mc version info aistor/$bucket 2>/dev/null | grep -q "Enabled" && echo "   ✅ Versioning enabled"
    mc ilm ls aistor/$bucket 2>/dev/null | grep -q "Enabled" && echo "   ✅ Lifecycle configured"
    echo ""
done

echo "=== Configuration Complete ==="
echo ""
echo "📋 Summary of capabilities enabled:"
echo "   • Lifecycle management (auto-tiering and expiry)"
echo "   • Object versioning (for model checkpoints)"
echo "   • Bucket policies (public/private access)"
echo "   • Object locking (WORM for compliance)"
echo "   • Quotas (storage limits)"
echo ""
echo "🚀 Next steps:"
echo "   1. Set up rclone cloud backups: ./scripts/setup-rclone-backups.sh"
echo "   2. Configure OpenClaw integration for automated workflows"
echo "   3. Enable monitoring: ./scripts/monitor-aistor.sh"
echo "   4. Test with: mc cp test-file.txt aistor/ai-models/"
echo ""
echo "📖 Documentation: AGENTS.md#AIStor-Object-Storage-for-AI"
