#!/bin/bash

# Rclone Setup Script
# Run this to configure rclone for cloud storage

echo "=== Rclone Setup ==="
echo ""
echo "Supported cloud storage providers:"
echo "Google Drive, Dropbox, OneDrive, Mega, Box, pCloud"
echo "AWS S3, Backblaze B2, Wasabi, DigitalOcean Spaces"
echo "FTP, SFTP, HTTP, WebDAV, and many more..."
echo ""
echo "To set up a remote storage:"
echo "1. Run: rclone config"
echo "2. Choose 'n' for new remote"
echo "3. Enter a name for your remote (e.g., 'gdrive')"
echo "4. Select the storage type number"
echo "5. Follow the prompts to authenticate"
echo ""
echo "Example usage after setup:"
echo "rclone ls gdrive:          # List files"
echo "rclone copy /local/file gdrive:remote/path  # Upload"
echo "rclone sync gdrive:remote /local/folder     # Sync"
echo "rclone mount gdrive: /mnt/cloud             # Mount"
echo ""

read -p "Would you like to run rclone config now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rclone config
fi