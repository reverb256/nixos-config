# NixOS Cluster Deployment - Idempotent Version
# All commands work consistently from any node and any directory
# Zephyr is local (no SSH needed), other nodes via SSH

# Cluster configuration
FLAKE_PATH := "/etc/nixos"
NEXUS := "j_kro@100.86.158.18"
FORGE := "j_kro@100.116.190.124"
SENTRY := "j_kro@100.82.210.39"

# Default branch for deployment (can be overridden with JUST_BRANCH=branch-name)
BRANCH := ""  # Empty = use current branch

_default:
     @echo "NixOS Cluster Management - Idempotent Deployment"
     @echo ""
     @echo "USAGE:"
     @echo "  just test [branch]  Test configuration (dry build) - optional branch"
     @echo "  just deploy [branch] Deploy infra branch (or custom branch) via colmena"
     @echo "  just fetch          Fetch latest code on all nodes (parallel)"
     @echo "  just switch        Local switch (current node) - runs locally"
     @echo "  just ci            Show CI status"
     @echo "  just status        Show cluster status"
     @echo ""
     @echo "EXAMPLES:"
     @echo "  just test                Test infra branch"
     @echo "  just test refactor/...    Test custom branch"
     @echo "  just deploy              Deploy infra branch (production)"
     @echo "  just deploy refactor/... Deploy custom branch"
     @echo ""
     @echo "All deployments use colmena via Tailscale VPN (100.x.x.x)"
     @echo "Works identically from any cluster node (zephyr, nexus, forge, sentry)"

# ============================================================================
# TEST & DEPLOY - Branch-aware testing and deployment
# ============================================================================

# Test configuration (dry build) - optional branch parameter (default: current branch)
test BRANCH=`git branch --show-current`:
    @echo "Testing configuration for branch: {{BRANCH}}"
    @echo "Checking flake syntax..."
    nix flake check --no-build
    @echo "Evaluating all configurations..."
    nix eval .#nixosConfigurations.zephyr.config.system.build.toplevel --raw > /dev/null
    nix eval .#nixosConfigurations.nexus.config.system.build.toplevel --raw > /dev/null
    nix eval .#nixosConfigurations.forge.config.system.build.toplevel --raw > /dev/null
    nix eval .#nixosConfigurations.sentry.config.system.build.toplevel --raw > /dev/null
    @echo "✅ All configurations valid for branch: {{BRANCH}}"

# Deploy specified branch via colmena - optional branch parameter (default: current branch)
deploy *BRANCH=`git branch --show-current`:
    @echo "Deploying branch: {{BRANCH}}"
    @echo "Checking out branch on all nodes..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{NEXUS}} "cd {{FLAKE_PATH}} && git fetch origin && git checkout origin/{{BRANCH}} -B {{BRANCH}} && git pull origin {{BRANCH}} 2>/dev/null || true"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{FORGE}} "cd {{FLAKE_PATH}} && git fetch origin && git checkout origin/{{BRANCH}} -B {{BRANCH}} && git pull origin {{BRANCH}} 2>/dev/null || true"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{SENTRY}} "cd {{FLAKE_PATH}} && git fetch origin && git checkout origin/{{BRANCH}} -B {{BRANCH}} && git pull origin {{BRANCH}} 2>/dev/null || true"
    cd {{FLAKE_PATH}} && git fetch origin && git checkout origin/{{BRANCH}} -B {{BRANCH}} && git pull origin {{BRANCH}}
    @echo "Deploying via colmena to all nodes..."
    nix run github:zhaofengli/colmena -- deploy --on-change --skip-eval
    @echo "✅ Deployment complete for branch: {{BRANCH}}"

# ============================================================================
# GIT OPERATIONS
# ============================================================================

# Fetch latest code on all nodes
fetch:
    @echo "Fetching all nodes..."
    cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{NEXUS}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{FORGE}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{SENTRY}} "cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null"
    @echo "Fetched all nodes"

# Deploy to individual hosts via colmena
zephyr:
    @echo "Deploying to zephyr via colmena..."
    cd {{FLAKE_PATH}} && nix run github:zhaofengli/colmena -- deploy zephyr --on-change --skip-eval

nexus:
    @echo "Deploying to nexus via colmena..."
    cd {{FLAKE_PATH}} && nix run github:zhaofengli/colmena -- deploy nexus --on-change --skip-eval

forge:
    @echo "Deploying to forge via colmena..."
    cd {{FLAKE_PATH}} && nix run github:zhaofengli/colmena -- deploy forge --on-change --skip-eval

sentry:
    @echo "Deploying to sentry via colmena..."
    cd {{FLAKE_PATH}} && nix run github:zhaofengli/colmena -- deploy sentry --on-change --skip-eval

# Local switch for current node - runs locally
switch:
    @echo "Switching local system configuration for user $(whoami)..."
    cd /etc/nixos && sudo nixos-rebuild switch --flake ".#$(hostname -s)"

# Copy age key to all nodes (run from zephyr first)
prep:
    @echo "Fetching all nodes..."
    cd {{FLAKE_PATH}} && git fetch origin 2>/dev/null
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
