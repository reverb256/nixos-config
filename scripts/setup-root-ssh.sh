#!/usr/bin/env bash
# ============================================================================
# SETUP ROOT SSH KEYS FOR DISTRIBUTED BUILDS
# ============================================================================
# This script copies the nixbuild SSH key from j_kro to root user
# and configures SSH for distributed builds across the cluster
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  log_error "This script must be run as root"
  log_info "Usage: sudo $0"
  exit 1
fi

# Source SSH key from j_kro
J_KRO_HOME="/home/j_kro"
NIXBUILD_KEY="${J_KRO_HOME}/.ssh/id_nixbuild"
NIXBUILD_PUB="${J_KRO_HOME}/.ssh/id_nixbuild.pub"
ROOT_SSH="/root/.ssh"

# Check if j_kro's key exists
if [[ ! -f "$NIXBUILD_KEY" ]]; then
  log_error "nixbuild key not found: $NIXBUILD_KEY"
  exit 1
fi

log_info "Creating root SSH directory structure..."
mkdir -p "$ROOT_SSH"
mkdir -p "$ROOT_SSH/sockets"
chmod 700 "$ROOT_SSH"
chmod 700 "$ROOT_SSH/sockets"

log_info "Copying nixbuild SSH key to root..."
cp "$NIXBUILD_KEY" "$ROOT_SSH/id_nixbuild"
cp "$NIXBUILD_PUB" "$ROOT_SSH/id_nixbuild.pub"
chown root:root "$ROOT_SSH/id_nixbuild" "$ROOT_SSH/id_nixbuild.pub"
chmod 600 "$ROOT_SSH/id_nixbuild"
chmod 644 "$ROOT_SSH/id_nixbuild.pub"

log_info "Creating SSH configuration for root..."
cat > "$ROOT_SSH/config" << 'EOF'
# Root SSH configuration for distributed builds
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /root/.ssh/known_hosts
  ConnectTimeout 5
  ServerAliveInterval 60
  ServerAliveCountMax 3

# Build machines using nixbuild key
Host nexus 10.1.1.120 100.86.158.18
  HostName 100.86.158.18
  User j_kro
  IdentityFile /root/.ssh/id_nixbuild
  IdentitiesOnly yes
  ControlPath /root/.ssh/sockets/ssh-%r@%h:%p

Host forge 10.1.1.130 100.95.222.45
  HostName 100.95.222.45
  User j_kro
  IdentityFile /root/.ssh/id_nixbuild
  IdentitiesOnly yes
  ControlPath /root/.ssh/sockets/ssh-%r@%h:%p

Host sentry 10.1.1.140 100.82.210.39
  HostName 100.82.210.39
  User j_kro
  IdentityFile /root/.ssh/id_nixbuild
  IdentitiesOnly yes
  ControlPath /root/.ssh/sockets/ssh-%r@%h:%p
EOF

chmod 600 "$ROOT_SSH/config"
chown root:root "$ROOT_SSH/config"

log_info "Setting up known_hosts..."
ssh-keygen -R nexus 2>/dev/null || true
ssh-keygen -R forge 2>/dev/null || true
ssh-keygen -R sentry 2>/dev/null || true
ssh-keygen -R 100.86.158.18 2>/dev/null || true
ssh-keygen -R 100.95.222.45 2>/dev/null || true
ssh-keygen -R 100.82.210.39 2>/dev/null || true

# Add new host keys
ssh-keyscan -H 100.86.158.18 100.95.222.45 100.82.210.39 2>/dev/null >> "$ROOT_SSH/known_hosts" || true
chown root:root "$ROOT_SSH/known_hosts"
chmod 644 "$ROOT_SSH/known_hosts"

log_info "Testing SSH connections..."
for host in nexus forge sentry; do
  echo -n "  Testing $host... "
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no j_kro@$host "echo OK" 2>&1 | grep -q "OK"; then
    echo -e "${GREEN}✓ Connected${NC}"
  else
    echo -e "${RED}✗ Failed${NC}"
  fi
done

log_info "Root SSH setup complete!"
log_info "You can now use 'sudo nixos-rebuild switch' for distributed builds"
