#!/usr/bin/env bash
# Template: New User Setup for Reverb-OS Cluster
# This script serves as a template to set up a new user with proper access to the Reverb-OS cluster
# It includes appropriate permissions, SSH key setup, and documentation for new users

set -e

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    REVERB-OS NEW USER SETUP TEMPLATE                       ║"
echo "║                                                                              ║"
echo "║    This template creates a new user with proper access to deploy on the      ║"
echo "║    4-node Reverb-OS cluster (zephyr, nexus, forge, sentry) via colmena       ║"
echo "║    through the nexus coordinator node. Follow the steps below to create      ║"
echo "║    a new user with appropriate permissions and documentation.              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Get new user information
read -p "Enter new username: " NEW_USER
read -p "Enter full name for the user: " FULL_NAME
read -p "Enter email for the user: " EMAIL

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                            STEP 1: CREATE USER                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "sudo useradd -m -c \"$FULL_NAME\" -s /bin/bash $NEW_USER"
echo ""

# Get confirmation
read -p "Should I execute the user creation? (yes/no): " CONFIRM
if [[ $CONFIRM == "yes" || $CONFIRM == "y" ]]; then
    sudo useradd -m -c "$FULL_NAME" -s /bin/bash "$NEW_USER"
    echo "User $NEW_USER created successfully!"
    
    # Set up home directory
    sudo mkdir -p /home/$NEW_USER/.ssh
    sudo chmod 700 /home/$NEW_USER/.ssh
    sudo chown $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
    echo "SSH directory created for $NEW_USER"
else
    echo "Skipping user creation step."
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                        STEP 2: SSH KEY SETUP                                ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "For the new user, SSH key authentication is required for cluster operations."
echo "The user should generate an SSH key pair and add the public key to authorized_hosts."
echo ""
echo "1. On the user's local machine, run:"
echo "   ssh-keygen -t ed25519 -C \"$EMAIL\""
echo ""
echo "2. The user should send their public key ($NEW_USER.pub) to the system administrator."
echo ""
echo "3. Once received, add to nexus:/home/$NEW_USER/.ssh/authorized_keys:"
echo "   cat user-provided-public-key.pub >> /home/$NEW_USER/.ssh/authorized_keys"
echo "   chmod 600 /home/$NEW_USER/.ssh/authorized_keys"
echo "   chown $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh/authorized_keys"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    STEP 3: GROUP MEMBERSHIP                                 ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Add the new user to necessary groups for cluster operations:"
echo ""
echo "sudo usermod -a -G nix-users,wheel,nogroup $NEW_USER"
echo "  - nix-users: Required for NixOS operations"
echo "  - wheel: Required for sudo access to deployment commands"
echo "  - nogroup: For file permissions (as per existing configuration)"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    STEP 4: SUDO PERMISSIONS                                 ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "The new user will need sudo access to run deployment commands. Ensure the"
echo "existing sudo rules in the NixOS configuration allow deployment operations:"
echo ""
echo "This typically includes permissions for:"
echo "  - Running nixos-rebuild and colmena commands"
echo "  - Accessing /etc/nixos/ directory"
echo "  - Executing deployment scripts"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    STEP 5: USER DOCUMENTATION                               ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Provide the new user with the following documentation:"
echo ""
echo "CLUSTER ACCESS:"
echo "- All cluster nodes accessible via Tailscale VPN:"
echo "  zephyr: 100.81.182.5"
echo "  nexus:  100.86.158.18  (coordinator node)"
echo "  forge:  100.116.190.124"
echo "  sentry: 100.82.210.39"
echo ""
echo "DEPLOYMENT COMMANDS:"
echo "  just deploy           # Deploy to all nodes (runs on nexus)"
echo "  just deploy-zephyr    # Deploy to zephyr only (runs on nexus)"
echo "  just deploy-nexus     # Deploy to nexus only (runs on nexus)"
echo "  just deploy-forge     # Deploy to forge only (runs on nexus)"
echo "  just deploy-sentry    # Deploy to sentry only (runs on nexus)"
echo "  just update           # Update flake + deploy all (runs on nexus)"
echo "  just switch           # Local switch only (runs locally)"
echo "  just cluster-status   # Check all nodes status"
echo ""
echo "SECURITY NOTES:"
echo "  - All operations use Tailscale encrypted connections"
echo "  - SSH keys required for node access"
echo "  - Operations run with user-specific permissions"
echo "  - Concurrent operations properly locked to prevent conflicts"
echo ""
echo "TROUBLESHOOTING:"
echo "  - If deployment is locked, wait for current operation to complete"
echo "  - Verify SSH connectivity to nexus before deploying"
echo "  - Check user permissions if commands fail with permission errors"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                        SETUP TEMPLATE COMPLETED                             ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "This template provides all necessary steps to add a new user to the Reverb-OS"
echo "cluster with appropriate permissions for deployment operations while "
echo "maintaining security through Tailscale VPN and proper user isolation."
echo ""
echo "Remember to update the documentation in /etc/nixos/CONTRIBUTING.md if "
echo "standard procedures change."