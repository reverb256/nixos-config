#!/usr/bin/env bash
# CNS Quick Start Script
# Zero-knowledge, zero-touch secret distribution setup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_DIR="/etc/nixos"

log() {
  echo "[$(date -Iseconds)] $*"
}

error() {
  echo "[$(date -Iseconds)] ERROR: $*" >&2
  exit 1
}

success() {
  echo "[$(date -Iseconds)] ✅ $*"
}

warn() {
  echo "[$(date -Iseconds)] ⚠️  $*"
}

info() {
  echo "[$(date -Iseconds)] ℹ️  $*"
}

# Phase 1: Generate CNS SSH key
phase1_generate_ssh_key() {
  log "Phase 1: Generating CNS SSH key..."

  cd "$NIXOS_DIR"

  # Check if key already exists
  if [ -f "secrets/cns-ssh-key.age" ]; then
    warn "cns-ssh-key.age already exists, skipping generation"
    return 0
  fi

  # Generate SSH key pair
  log "Generating SSH key pair..."
  ssh-keygen -t ed25519 -f /tmp/cns-ssh-key -N "" -C "cns@zephyr"

  # Encrypt private key with sops-nix
  log "Encrypting private key..."
  sops --encrypt secrets/cns-ssh-key.age /tmp/cns-ssh-key

  # Cleanup temp files
  rm -f /tmp/cns-ssh-key /tmp/cns-ssh-key.pub

  success "CNS SSH key generated and encrypted"
}

# Phase 2: Extract public key
phase2_extract_public_key() {
  log "Phase 2: Extracting public key..."

  cd "$NIXOS_DIR"

  # Decrypt to get public key
  local key_output=$(sops --decrypt secrets/cns-ssh-key.age | ssh-keygen -y -f /dev/stdin)

  if [ -z "$key_output" ]; then
    error "Failed to extract public key"
  fi

  success "Public key extracted: $key_output"

  # Save to file
  echo "$key_output" > /tmp/cns-public-key.txt
  log "Public key saved to /tmp/cns-public-key.txt"
}

# Phase 3: Add modules to NixOS
phase3_add_modules() {
  log "Phase 3: Adding CNS modules to NixOS..."

  cd "$NIXOS_DIR"

  # Copy modules
  log "Copying CNS modules..."
  cp /tmp/cns-watcher.nix modules/system/cns-watcher.nix
  cp /tmp/cns-receiver.nix modules/system/cns-receiver.nix
  cp /tmp/cns-setup.nix modules/system/cns-setup.nix

  # Add to default.nix
  local default_nix="modules/system/default.nix"
  if ! grep -q "cns-watcher" "$default_nix"; then
    log "Adding CNS modules to $default_nix..."
    echo "" >> "$default_nix"
    echo "# CNS: Zero-knowledge automatic secret distribution" >> "$default_nix"
    echo "cns-watcher = import ./cns-watcher.nix;" >> "$default_nix"
    echo "cns-receiver = import ./cns-receiver.nix;" >> "$default_nix"
    echo "cns-setup = import ./cns-setup.nix;" >> "$default_nix"
  fi

  success "CNS modules added to NixOS"
}

# Phase 4: Enable CNS on Zephyr
phase4_enable_zephyr() {
  log "Phase 4: Enabling CNS on Zephyr..."

  local zephyr_config="hosts/zephyr/default.nix"
  local public_key=$(cat /tmp/cns-public-key.txt)

  # Add CNS configuration
  if ! grep -q "services.cns-watcher" "$zephyr_config"; then
    log "Adding CNS configuration to $zephyr_config..."
    cat >> "$zephyr_config" << 'EOF'

# CNS: Zero-knowledge automatic secret distribution
services.cns-setup.enable = true;
services.cns-watcher.enable = true;
EOF
  fi

  success "CNS enabled on Zephyr"
}

# Phase 5: Configure remote nodes
phase5_configure_remotes() {
  log "Phase 5: Configuring remote nodes..."

  local public_key=$(cat /tmp/cns-public-key.txt)
  local nodes=("nexus" "forge" "sentry")

  for node in "''${nodes[@]}"; do
    local node_config="hosts/$node/default.nix"

    if [ ! -f "$node_config" ]; then
      warn "Node config not found: $node_config, skipping"
      continue
    fi

    # Add CNS receiver configuration
    if ! grep -q "services.cns-receiver" "$node_config"; then
      log "Adding CNS receiver to $node_config..."
      cat >> "$node_config" << EOF

# CNS: Zero-knowledge automatic secret distribution
services.cns-receiver = {
  enable = true;
  sshPublicKey = "$public_key";
};
EOF
    fi
  done

  success "Remote nodes configured"
}

# Phase 6: Deploy and verify
phase6_deploy_verify() {
  log "Phase 6: Deploying configuration..."

  cd "$NIXOS_DIR"

  # Add to git
  log "Committing changes..."
  git add modules/system/cns-*.nix
  git add hosts/*/default.nix
  git add secrets/cns-ssh-key.age
  git commit -m "feat(secrets): add CNS zero-knowledge automatic secret distribution"

  # Deploy to Zephyr
  log "Deploying to Zephyr..."
  just switch || error "Failed to deploy to Zephyr"

  # Extract public key again (now that it's decrypted)
  phase2_extract_public_key

  # Deploy to all nodes
  log "Deploying to all nodes..."
  just deploy || error "Failed to deploy to all nodes"

  success "Configuration deployed"
}

# Phase 7: Verification
phase7_verify() {
  log "Phase 7: Verifying CNS operation..."

  # Check CNS watcher on Zephyr
  if systemctl is-active --quiet cns-watcher; then
    success "CNS watcher is running on Zephyr"
  else
    error "CNS watcher is not running on Zephyr"
  fi

  # Check CNS receiver on remote nodes
  local nodes=("nexus" "forge" "sentry")
  for node in "''${nodes[@]}"; do
    if ssh "$node" 'bash --norc --noprofile -c "systemctl is-active --quiet cns-receive@$node.socket"'; then
      success "CNS receiver socket is listening on $node"
    else
      error "CNS receiver socket is not listening on $node"
    fi
  done

  # Check logs
  log "Checking CNS watcher logs..."
  if [ -f /var/log/cns/watcher.log ]; then
    log "Last 5 lines from watcher log:"
    tail -5 /var/log/cns/watcher.log | sed 's/^/  /'
  else
    warn "Watcher log not found yet"
  fi

  success "CNS verification complete"
}

# Main execution
main() {
  log "=== CNS Quick Start ==="
  log "Zero-knowledge, zero-touch secret distribution"
  log ""

  # Check prerequisites
  if [ ! -d "$NIXOS_DIR" ]; then
    error "NixOS directory not found: $NIXOS_DIR"
  fi

  if ! command -v sops &> /dev/null; then
    error "sops not found. Install with: nix-shell -p sops"
  fi

  # Run phases
  phase1_generate_ssh_key
  phase2_extract_public_key
  phase3_add_modules
  phase4_enable_zephyr
  phase5_configure_remotes
  phase6_deploy_verify
  phase7_verify

  log ""
  success "=== CNS Setup Complete ==="
  log ""
  info "Next steps:"
  info "1. CNS is now running and watching for secret changes"
  info "2. Add new secrets: cd /etc/nixos && sops --encrypt secrets/new.yaml"
  info "3. Register in registry: modules/system/sops-secrets-registry.nix"
  info "4. Deploy: just deploy"
  info "5. CNS automatically syncs secrets to all nodes"
  info ""
  info "Monitoring:"
  info "  Zephyr logs:  tail -f /var/log/cns/watcher.log"
  info "  Node logs:   ssh nexus 'tail -f /var/log/cns/receiver.log'"
  info "  Health check: journalctl -u cns-health -f"
  log ""
}

# Run main function
main "$@"