# NixOS Cluster Deployment - Idempotent Version
# All commands work consistently from any node and any directory
# Coordinated from nexus (deployment coordinator) via SSH

_default:
    @echo "NixOS Cluster Management - Idempotent Deployment"
    @echo ""
    @echo "USAGE:"
    @echo "  just build         Build configs (dry run) - runs on nexus"
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

# Build all configurations (dry run) - runs on nexus with session isolation
build:
    @echo "Building all configurations (dry run)..."
    /etc/nixos/scripts/just-cluster build

# Deploy to all cluster hosts - runs on nexus with session isolation
deploy:
    @echo "Deploying to all cluster hosts (with session isolation)..."
    /etc/nixos/scripts/just-cluster deploy

# Deploy to individual hosts - runs on nexus with session isolation
zephyr:
    @echo "Deploying to zephyr (with session isolation)..."
    /etc/nixos/scripts/just-cluster zephyr

nexus:
    @echo "Deploying to nexus (with session isolation)..."
    /etc/nixos/scripts/just-cluster nexus

forge:
    @echo "Deploying to forge (with session isolation)..."
    /etc/nixos/scripts/just-cluster forge

sentry:
    @echo "Deploying to sentry (with session isolation)..."
    /etc/nixos/scripts/just-cluster sentry

# Local switch for current node - runs locally with user isolation
switch:
    @echo "Switching local system configuration for user $(whoami)..."
    cd /etc/nixos && sudo -u $(id -un) -H nixos-rebuild switch --flake ".#$(hostname -s)"

# Update flake and deploy all - runs on nexus with session isolation
update:
    @echo "Updating flake and deploying to all hosts (with session isolation)..."
    /etc/nixos/scripts/just-cluster update

# CI status (no session isolation needed)
ci:
    /etc/nixos/scripts/just-cluster ci

# Cluster info (no session isolation needed)
status:
    /etc/nixos/scripts/just-cluster status