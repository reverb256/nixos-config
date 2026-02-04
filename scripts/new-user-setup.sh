#!/usr/bin/env bash
# New User Setup for Reverb-OS Cluster
# Creates a new user with proper access to deploy on the 4-node cluster

set -e

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    REVERB-OS NEW USER SETUP                                 ║"
echo "║                                                                              ║"
echo "║    This script creates a new user with proper access to deploy on the        ║"
echo "║    4-node Reverb-OS cluster (zephyr, nexus, forge, sentry) via colmena       ║"
echo "║    through the nexus coordinator node.                                      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

# Get new user information
read -p "Enter new username: " NEW_USER

# Validate username
if [[ ! "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || [ ${#NEW_USER} -gt 32 ]; then
    echo "Invalid username format. Use lowercase letters, numbers, underscores, hyphens. Max 32 chars."
    exit 1
fi

read -p "Enter full name for the user: " FULL_NAME

# Check if user already exists
if id "$NEW_USER" &>/dev/null; then
    echo "User $NEW_USER already exists. Exiting."
    exit 1
fi

echo ""
echo "Creating user: $NEW_USER ($FULL_NAME)"
echo "====================================="

# Step 1: Create user with home directory
echo "1. Creating user account..."
useradd -m -c "$FULL_NAME" -s /bin/bash "$NEW_USER"
echo "   ✓ User $NEW_USER created successfully"

# Step 2: Set up SSH directory
echo "2. Setting up SSH directory..."
mkdir -p "/home/$NEW_USER/.ssh"
chmod 700 "/home/$NEW_USER/.ssh"
chown "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
echo "   ✓ SSH directory created with proper permissions"

# Step 3: Add user to necessary groups
echo "3. Adding user to groups..."
usermod -a -G nix-users,wheel "$NEW_USER"
echo "   ✓ Added $NEW_USER to nix-users and wheel groups"

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    USER CREATED SUCCESSFULLY                                ║"
echo "║                                                                              ║"
echo "║    Username: $NEW_USER                                                      ║"
echo "║    Full Name: $FULL_NAME                                                    ║"
echo "║    Groups: nix-users, wheel                                                 ║"
echo "║    Home Directory: /home/$NEW_USER                                         ║"
echo "║    SSH Directory: /home/$NEW_USER/.ssh                                    ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

echo "Next steps for the new user:"
echo "1. Set password: sudo passwd $NEW_USER"
echo "2. Or configure SSH key authentication for passwordless login"
echo "3. Share this information with the new user:"
echo ""
echo "   CLUSTER ACCESS:"
echo "   - All cluster nodes accessible via Tailscale VPN:"
echo "     zephyr: 100.81.182.5"
echo "     nexus:  100.86.158.18  (coordinator node)"
echo "     forge:  100.116.190.124"
echo "     sentry: 100.82.210.39"
echo ""
echo "   DEPLOYMENT COMMANDS (run from /etc/nixos/ directory):"
echo "     just deploy           # Deploy to all nodes (runs on nexus)"
echo "     just deploy-zephyr    # Deploy to zephyr only (runs on nexus)"
echo "     just deploy-nexus     # Deploy to nexus only (runs on nexus)"
echo "     just deploy-forge     # Deploy to forge only (runs on nexus)"
echo "     just deploy-sentry    # Deploy to sentry only (runs on nexus)"
echo "     just update           # Update flake + deploy all (runs on nexus)"
echo "     just switch           # Local switch only (runs locally)"
echo "     just cluster-status   # Check all nodes status"
echo ""
echo "   SECURITY NOTES:"
echo "     - All operations use Tailscale encrypted connections"
echo "     - SSH keys required for node access"
echo "     - Operations run with user-specific permissions"
echo "     - Concurrent operations properly locked to prevent conflicts"
echo ""
echo "   TROUBLESHOOTING:"
echo "     - If deployment is locked, wait for current operation to complete"
echo "     - Verify SSH connectivity to nexus before deploying"
echo "     - Check user permissions if commands fail with permission errors"
echo ""