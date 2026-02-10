# NixOS Cluster Deployment - Idempotent Version
# All commands work consistently from any node and any directory
# Zephyr is local (no SSH needed), other nodes via SSH

# Cluster configuration (using Tailscale IPs for cluster management)
FLAKE_PATH := "/etc/nixos"
NEXUS := "j_kro@100.86.158.18"   # Local: 10.1.1.120
FORGE := "j_kro@100.95.222.45"   # Local: 10.1.1.130
SENTRY := "j_kro@100.82.210.39"   # Local: 10.1.1.140
ZEPHYR := "root@100.81.182.5"   # Local: 10.1.1.110, Tailscale 100.81.182.5

# Default branch for deployment (can be overridden with JUST_BRANCH=branch-name)
BRANCH := ""  # Empty = use current branch

_default:
     @echo "NixOS Cluster Management - Idempotent Deployment"
     @echo ""
     @echo "USAGE:"
     @echo "  just sync           Commit, push, and deploy changes to all nodes"
     @echo "  just test [branch]  Test configuration (dry build) - optional branch"
     @echo "  just deploy [branch] Deploy infra branch (or custom branch) via colmena"
     @echo "  just fetch          Fetch latest code on all nodes (parallel)"
     @echo "  just switch        Local switch (current node) - runs locally"
     @echo "  just ci            Show CI status"
     @echo "  just status        Show cluster status"
     @echo ""
     @echo "EXAMPLES:"
     @echo "  just sync                Commit, push, and deploy current changes"
     @echo "  just test                Test infra branch"
     @echo "  just test refactor/...    Test custom branch"
     @echo "  just deploy              Deploy infra branch (production)"
     @echo "  just deploy refactor/... Deploy custom branch"
     @echo ""
     @echo "All deployments use colmena via Tailscale VPN (100.x.x.x)"
     @echo "Works identically from any cluster node (zephyr, nexus, forge, sentry)"

# ============================================================================
# SYNC & DEPLOY - Commit, push, and deploy all nodes
# ============================================================================

# Commit, push, and deploy current changes to all nodes
sync BRANCH=`git branch --show-current`:
    @echo "Syncing changes to branch: {{BRANCH}}"
    @echo "Checking for uncommitted changes..."
    if [ -n "$(git status --porcelain)" ]; then \
      echo "No changes to sync"; \
      exit 0; \
    fi
    @echo "Committing changes..."
    git add -A
    git commit -m "sync: Auto-commit before deployment $(date '+%Y-%m-%d %H:%M:%S')"
    @echo "Pushing to origin..."
    git push origin {{BRANCH}}
    @echo "Deploying to all nodes..."
    just deploy {{BRANCH}}
    @echo "✅ Sync complete for branch: {{BRANCH}}"

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
    @echo "Pausing mining on all nodes..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{NEXUS}} "mining-build-wrapper/bin/mining-pause" 2>/dev/null || true
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{ZEPHYR}} "mining-build-wrapper/bin/mining-pause" 2>/dev/null || true
    @echo "Checking out branch on all nodes..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{NEXUS}} "cd {{FLAKE_PATH}} && git fetch origin && git checkout origin/{{BRANCH}} -B {{BRANCH}} && git pull origin {{BRANCH}} 2>/dev/null || true"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{FORGE}} "cd {{FLAKE_PATH}} && git fetch origin && git checkout origin/{{BRANCH}} -B {{BRANCH}} && git pull origin {{BRANCH}} 2>/dev/null || true"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{SENTRY}} "cd {{FLAKE_PATH}} && git fetch origin && git checkout origin/{{BRANCH}} -B {{BRANCH}} && git pull origin {{BRANCH}} 2>/dev/null || true"
    @echo "Deploying via colmena to all nodes..."
    nix run github:zhaofengli/colmena -- apply --on @all --activate --build-on-target --reboot 0
    @echo "Resuming mining on all nodes..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{NEXUS}} "mining-build-wrapper/bin/mining-resume" 2>/dev/null || true
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no {{ZEPHYR}} "mining-build-wrapper/bin/mining-resume" 2>/dev/null || true
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
    cd {{FLAKE_PATH}} && nix run github:zhaofengli/colmena -- apply zephyr --activate --build-on-target --reboot 0

nexus:
    @echo "Deploying to nexus via colmena..."
    cd {{FLAKE_PATH}} && nix run github:zhaofengli/colmena -- apply nexus --activate --build-on-target --reboot 0

forge:
    @echo "Deploying to forge via colmena..."
    cd {{FLAKE_PATH}} && nix run github:zhaofengli/colmena -- apply forge --activate --build-on-target --reboot 0

sentry:
    @echo "Deploying to sentry via colmena..."
    cd {{FLAKE_PATH}} && nix run github:zhaofengli/colmena -- apply sentry --activate --build-on-target --reboot 0

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
