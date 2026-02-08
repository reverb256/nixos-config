# NixOS Cluster Deployment - Idempotent Version
# All commands work consistently from any node and any directory
# Coordinated from nexus (deployment coordinator) via SSH

# Cluster configuration
FLAKE_PATH := "/etc/nixos"
ZEPHYR := "j_kro@10.1.1.110"
NEXUS := "j_kro@10.1.1.120"
FORGE := "j_kro@10.1.1.130"
SENTRY := "j_kro@10.1.1.140"

_default:
     @echo "NixOS Cluster Management - Idempotent Deployment"
     @echo ""
     @echo "USAGE:"
     @echo "  just build         Build configs (dry run) - runs on nexus"
     @echo "  just fetch          Fetch latest code on all nodes (parallel)"
     @echo "  just deploy        Deploy to all hosts - runs on nexus"
     @echo "  just zephyr        Deploy to zephyr - runs on nexus"
     @echo "  just nexus         Deploy to nexus - runs on nexus"
     @echo "  just forge         Deploy to forge - runs on nexus"
     @echo "  just sentry        Deploy to sentry - runs on nexus"
     @echo "  just switch        Local switch (current node) - runs locally"
     @echo "  just update        Update flake + deploy all - runs on nexus"
     @echo "  just ci            Show CI status"
     @echo "  just status        Show cluster status"
     @echo ""
     @echo "All commands execute on nexus (deployment coordinator) via SSH"
     @echo "except 'switch' which runs locally on the current node"
     @echo "Works identically from any cluster node (zephyr, nexus, forge, sentry)"

# ============================================================================
# GNU PARALLEL - Parallel command execution across nodes
# ============================================================================
# Uses GNU parallel to execute SSH commands in parallel across all cluster nodes
# GNU parallel syntax: parallel [options] [command] [arguments]
# Example: parallel --tag "tag-{{n}}" -- ssh user@host "command"
# Documentation: https://www.gnu.org/software/parallel/

# Fetch latest code on all nodes
fetch:
    @echo "Fetching all nodes..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{ZEPHYR}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{NEXUS}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    @echo "Fetched all nodes"

# Build all configurations (sequential) - runs on nexus
build:
    @echo "Building all configurations..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{ZEPHYR}} "cd {{FLAKE_PATH}} && nix build .#zephyr 2>&1" | tee /tmp/just-zephyr.out
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{NEXUS}} "cd {{FLAKE_PATH}} && nix build .#nexus 2>&1" | tee /tmp/just-nexus.out
    @echo "Built all nodes"

# Update flake and deploy all - runs on nexus with session isolation
update:
    @echo "Updating flake and deploying to all hosts..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{ZEPHYR}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{NEXUS}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    @echo "Deploying to all cluster hosts (with session isolation)..."
    /etc/nixos/scripts/just-cluster deploy

# Deploy to all cluster hosts - runs on nexus with session isolation
deploy:
    @echo "Fetching latest code on all nodes..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{ZEPHYR}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{NEXUS}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{FORGE}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{SENTRY}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    @echo "Deployment complete for all nodes"

# Deploy to individual hosts - runs on nexus with session isolation
zephyr:
    @echo "Fetching latest code on zephyr..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{ZEPHYR}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    @echo "Deploying to zephyr (with session isolation)..."
    /etc/nixos/scripts/just-cluster zephyr

nexus:
    @echo "Fetching latest code on nexus..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{NEXUS}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    @echo "Deploying to nexus (with session isolation)..."
    /etc/nixos/scripts/just-cluster nexus

forge:
    @echo "Fetching latest code on forge..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{FORGE}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    @echo "Deploying to forge (with session isolation)..."
    /etc/nixos/scripts/just-cluster forge

sentry:
    @echo "Skipping sentry deployment (kernel issue workaround pending)"
    # @echo "Fetching latest code on sentry..."
    # @parallel --tag "just-sentry.out" -- \
    #     ssh $SSH_OPTS "cd ${FLAKE_PATH} && git fetch origin 2>/dev/null"
    # @echo "Deploying to sentry (with session isolation)..."
    # /etc/nixos/scripts/just-cluster sentry

# Local switch for current node - runs locally
switch:
    @echo "Switching local system configuration for user $(whoami)..."
    cd /etc/nixos && sudo nixos-rebuild switch --flake ".#$(hostname -s)"

# Copy age key to all nodes (run from zephyr first)
prep:
    @echo "Fetching all nodes..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{ZEPHYR}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{NEXUS}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{FORGE}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{SENTRY}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    @echo "Copying age key to all nodes..."
    /etc/nixos/scripts/just-cluster prep

# Deploy from current host (alternative to just-cluster)
push:
    @echo "Deploying from current host..."
    /etc/nixos/scripts/just-cluster push

# ============================================================================
#  SERVICE MANAGEMENT
# ============================================================================

# View system logs
logs:
    @echo "Viewing recent system logs..."
    sudo journalctl -f

# Check WiVRn/Avahi status
status-vr:
    @echo "Checking Avahi daemon status..."
    sudo systemctl status avahi-daemon
    @echo ""
    @echo "Checking OpenRazer status..."
    sudo systemctl status openrazer-daemon || echo "OpenRazer may not be running"

# Restart WiVRn services
restart-vr:
    @echo "Restarting WiVRn services..."
    sudo systemctl restart avahi-daemon
    @echo "Avahi restarted"
