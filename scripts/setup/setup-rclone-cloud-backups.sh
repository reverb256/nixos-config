#!/usr/bin/env bash
# Rclone Cloud Backup Setup for  AIStor
# Configures automated cloud backups for AI data

set -e

AISTOR_ENDPOINT="${AISTOR_ENDPOINT:-http://10.1.1.120:9000}"
RCLONE_CONFIG_DIR="/var/lib/lobster/.config/rclone"
RCLONE_CONFIG="$RCLONE_CONFIG_DIR/rclone.conf"

echo "=== Rclone Cloud Backup Setup ==="
echo "AIStor Endpoint: $AISTOR_ENDPOINT"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
   echo "⚠ Warning: Running as root. Rclone config should be as 'lobster' user."
   echo "Consider running: sudo -u lobster -i $0"
   echo ""
fi

# Ensure rclone is installed
if ! command -v rclone &> /dev/null; then
    echo "❌ rclone not found. Please install rclone first:"
    echo "   nix-shell -p rclone"
    exit 1
fi

echo "✓ rclone is installed"
echo ""

# Create config directory
echo "Setting up rclone configuration directory..."
mkdir -p "$RCLONE_CONFIG_DIR"
echo "✓ Created: $RCLONE_CONFIG_DIR"
echo ""

# Function to configure a remote
configure_remote() {
    local remote_name=$1
    local remote_type=$2
    
    echo "--- Configuring $remote_name ($remote_type) ---"
    
    case $remote_type in
        "s3")
            echo "For S3-compatible storage (AWS, Wasabi, etc.):"
            rclone config create "$remote_name" s3 \
                provider="AWS" \
                env_auth=false \
                access_key_id="" \
                secret_access_key="" \
                region="us-east-1" \
                endpoint=""
            ;;
        "drive")
            echo "For Google Drive:"
            echo "1. Visit https://console.cloud.google.com/"
            echo "2. Create a project and enable Google Drive API"
            echo "3. Create OAuth credentials"
            echo "4. Run: rclone config reconnect $remote_name:"
            rclone config create "$remote_name" drive \
                client_id="" \
                client_secret="" \
                scope=drive
            ;;
        "b2")
            echo "For Backblaze B2:"
            rclone config create "$remote_name" b2 \
                account="" \
                key=""
            ;;
        "azureblob")
            echo "For Azure Blob Storage:"
            rclone config create "$remote_name" azureblob \
                account="" \
                key=""
            ;;
        "dropbox")
            echo "For Dropbox:"
            rclone config create "$remote_name" dropbox \
                client_id="" \
                client_secret=""
            ;;
        *)
            echo "Unknown remote type: $remote_type"
            return 1
            ;;
    esac
    
    echo "✓ Remote '$remote_name' created"
    echo "  Run 'rclone config reconnect $remote_name:' to authenticate"
    echo ""
}

# Function to add AIStor as S3 remote
configure_aistor_remote() {
    echo "--- Configuring AIStor S3 Remote ---"
    
    # Read credentials from environment or prompt
    if [ -f "/run/agenix/minio-cache-credentials" ]; then
        echo "✓ Found credentials in /run/agenix/minio-cache-credentials"
        # Source the credentials
        set -a
        source /run/agenix/minio-cache-credentials
        set +a
    else
        echo "⚠ Credentials not found in agenix. Please enter manually:"
        read -p "Access Key: " MINIO_ACCESS_KEY
        read -s -p "Secret Key: " MINIO_SECRET_KEY
        echo ""
    fi
    
    # Create S3 remote for AIStor
    rclone config create "aistor" s3 \
        provider="Minio" \
        env_auth="false" \
        access_key_id="${MINIO_ACCESS_KEY:-minioadmin}" \
        secret_access_key="${MINIO_SECRET_KEY:-}" \
        endpoint="$AISTOR_ENDPOINT" \
        region="us-east-1" \
        force_path_style="true"
    
    echo "✓ AIStor remote configured"
    echo "  Test with: rclone ls aistor:ai-models"
    echo ""
}

# Interactive menu
echo "Choose cloud backup destination:"
echo ""
echo "1) Google Drive (gdrive) - Free 15GB, good for small backups"
echo "2) Backblaze B2 (b2) - $0.005/GB/month, S3-compatible"
echo "3) Wasabi (wasabi) - $6.99/TB/month, unlimited egress"
echo "4) AWS S3 (s3) - Standard cloud storage, glacier option"
echo "5) Azure Blob (azure) - Microsoft's cloud storage"
echo "6) Dropbox (dropbox) - Free 2GB, good for sync"
echo "7) Skip cloud setup (configure later)"
echo ""

read -p "Enter choice (1-7): " choice

case $choice in
    1)
        configure_remote "gdrive" "drive"
        BACKUP_REMOTE="gdrive"
        ;;
    2)
        configure_remote "b2" "b2"
        BACKUP_REMOTE="b2"
        ;;
    3)
        configure_remote "wasabi" "s3"
        BACKUP_REMOTE="wasabi"
        ;;
    4)
        configure_remote "s3" "s3"
        BACKUP_REMOTE="s3"
        ;;
    5)
        configure_remote "azure" "azureblob"
        BACKUP_REMOTE="azure"
        ;;
    6)
        configure_remote "dropbox" "dropbox"
        BACKUP_REMOTE="dropbox"
        ;;
    7)
        echo "Skipping cloud setup. You can configure later with 'rclone config'"
        BACKUP_REMOTE=""
        ;;
    *)
        echo "Invalid choice. You can configure later with 'rclone config'"
        BACKUP_REMOTE=""
        ;;
esac

# Always configure AIStor remote
configure_aistor_remote

# Create backup scripts directory
BACKUP_SCRIPTS_DIR="/var/lib/lobster/backup-scripts"
mkdir -p "$BACKUP_SCRIPTS_DIR"

# Create automated backup script
echo "Creating automated backup scripts..."

cat > "$BACKUP_SCRIPTS_DIR/backup-models.sh" << 'EOF'
#!/usr/bin/env bash
# Automated backup of ai-models bucket to cloud
set -e

REMOTE="${1:-gdrive}"
LOG_FILE="/var/lib/lobster/storage/logs/backup-models-$(date +%Y%m%d).log"

mkdir -p "$(dirname "$LOG_FILE")"

echo "[$(date)] Starting models backup to $REMOTE..." >> "$LOG_FILE"

rclone sync \
    aistor:ai-models \
    "$REMOTE:-ai-models-backup" \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --log-file "$LOG_FILE" \
    --log-level INFO \
    --exclude ".tmp/**" \
    --exclude "*.temp"

echo "[$(date)] Models backup complete" >> "$LOG_FILE"
EOF
chmod +x "$BACKUP_SCRIPTS_DIR/backup-models.sh"

cat > "$BACKUP_SCRIPTS_DIR/backup-experiments.sh" << 'EOF'
#!/usr/bin/env bash
# Automated backup of experiments bucket to cloud
set -e

REMOTE="${1:-gdrive}"
LOG_FILE="/var/lib/lobster/storage/logs/backup-experiments-$(date +%Y%m%d).log"

mkdir -p "$(dirname "$LOG_FILE")"

echo "[$(date)] Starting experiments backup to $REMOTE..." >> "$LOG_FILE"

rclone sync \
    aistor:experiments \
    "$REMOTE:-experiments-backup" \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --log-file "$LOG_FILE" \
    --log-level INFO

echo "[$(date)] Experiments backup complete" >> "$LOG_FILE"
EOF
chmod +x "$BACKUP_SCRIPTS_DIR/backup-experiments.sh"

cat > "$BACKUP_SCRIPTS_DIR/backup-all.sh" << EOF
#!/usr/bin/env bash
# Backup all AIStor buckets to cloud
set -e

REMOTE="\${1:-${BACKUP_REMOTE:-gdrive}}"

if [ -z "\$REMOTE" ]; then
    echo "Usage: \$0 <remote-name>"
    echo "Example: \$0 gdrive"
    exit 1
fi

echo "=== Starting full backup to \$REMOTE ==="

echo "Backing up ai-models..."
$BACKUP_SCRIPTS_DIR/backup-models.sh "\$REMOTE"

echo "Backing up experiments..."
$BACKUP_SCRIPTS_DIR/backup-experiments.sh "\$REMOTE"

echo "=== Full backup complete ==="
EOF
chmod +x "$BACKUP_SCRIPTS_DIR/backup-all.sh"

echo "✓ Backup scripts created in $BACKUP_SCRIPTS_DIR"
echo ""

# Create systemd timer for automated backups (if requested)
echo ""
read -p "Setup automated daily backups? (y/n): " setup_timer

if [[ $setup_timer =~ ^[Yy]$ ]]; then
    echo "Creating systemd timer for automated backups..."
    
    # Create systemd service
    cat > /tmp/-backup.service << EOF
[Unit]
Description= AIStor Cloud Backup
After=network-online.target

[Service]
Type=oneshot
User=lobster
Group=lobster
ExecStart=$BACKUP_SCRIPTS_DIR/backup-all.sh ${BACKUP_REMOTE:-gdrive}
Environment="RCLONE_CONFIG=$RCLONE_CONFIG"
EOF

    # Create systemd timer
    cat > /tmp/-backup.timer << EOF
[Unit]
Description=Daily backup of  AIStor to cloud

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

    echo ""
    echo "To enable automated backups, run:"
    echo "  sudo cp /tmp/-backup.service /etc/systemd/system/"
    echo "  sudo cp /tmp/-backup.timer /etc/systemd/system/"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl enable --now -backup.timer"
    echo ""
fi

# Summary
echo "=== Setup Complete ==="
echo ""
echo "Configuration files:"
echo "  Rclone config: $RCLONE_CONFIG"
echo "  Backup scripts: $BACKUP_SCRIPTS_DIR"
echo ""
echo "Manual backup commands:"
echo "  $BACKUP_SCRIPTS_DIR/backup-models.sh [remote]"
echo "  $BACKUP_SCRIPTS_DIR/backup-experiments.sh [remote]"
echo "  $BACKUP_SCRIPTS_DIR/backup-all.sh [remote]"
echo ""
echo "Test commands:"
echo "  rclone ls aistor:ai-models"
echo "  rclone ls aistor:experiments"
if [ -n "$BACKUP_REMOTE" ]; then
    echo "  rclone ls $BACKUP_REMOTE:-ai-models-backup"
fi
echo ""
echo "Next steps:"
echo "  1. Authenticate your cloud remote:"
if [ -n "$BACKUP_REMOTE" ]; then
    echo "     rclone config reconnect $BACKUP_REMOTE:"
fi
echo "  2. Test the connection:"
echo "     rclone ls $BACKUP_REMOTE:"
echo "  3. Run initial backup:"
echo "     $BACKUP_SCRIPTS_DIR/backup-all.sh"
echo ""
