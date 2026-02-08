# NixOS Cluster Deployment - Idempotent Version
# All commands work consistently from any node and any directory
# Coordinated from nexus (deployment coordinator) via SSH

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

# Fetch latest code on all nodes in parallel
fetch:
    @echo "Fetching all nodes (parallel)..."
    @parallel --tag "just-fetch-{{n}}.out" -- \
        ssh $SSH_OPTS ${{HOST}} "cd ${FLAKE_PATH} && git fetch origin 2>/dev/null" & \
    ::: ::: HOST zephyr nexus forge sentry
    @wait
    @echo "Fetched all nodes"

# Build all configurations (parallel) - runs on nexus
build:
    @echo "Building all configurations (parallel)..."
    @parallel --tag "just-build-{{n}}.out" -- \
        ssh $SSH_OPTS ${{HOST}} "cd ${FLAKE_PATH} && nix build .#${HOST} 2>&1" | tee /tmp/just-{{HOST}}.out \
        ::: ::: HOST zephyr nexus forge sentry
    @wait
    @parallel --tag "just-build-done.{{n}}.out" -- \
        echo "Built {{HOST}}"
        ::: ::: HOST zephyr nexus forge sentry

# Update flake and deploy all - runs on nexus with session isolation
update:
    @echo "Updating flake and deploying to all hosts (parallel)..."
    @parallel --tag "just-update-{{n}}.out" -- \
        @for node in zephyr nexus forge sentry; do \
            echo "Fetching on ${{node}}..."; \
            ssh $SSH_OPTS "${NODES[$node]}" "cd ${FLAKE_PATH} && git fetch origin 2>/dev/null"; \
        done
    @wait
    @parallel --tag "just-update-done.{{n}}.out" -- \
        echo "Fetched {{node}}"
        ::: ::: HOST zephyr nexus forge sentry
    @echo "Deploying to all cluster hosts (with session isolation)..."
    /etc/nixos/scripts/just-cluster deploy

# Deploy to all cluster hosts - runs on nexus with session isolation
deploy:
    @echo "Fetching latest code on all nodes (parallel)..."
    @parallel --tag "just-deploy.{{n}}.out" -- \
        @for node in zephyr nexus forge sentry; do \
            echo "Fetching on ${{node}}..."; \
            ssh $SSH_OPTS "${NODES[$node]}" "cd ${FLAKE_PATH} && git fetch origin 2>/dev/null"; \
        done
    @wait
    @parallel --tag "just-deploy-done.{{n}}.out" -- \
        echo "Deployed {{node}}"
        ::: ::: HOST zephyr nexus forge sentry
    @echo "Deployment complete for all nodes"

# Deploy to individual hosts - runs on nexus with session isolation
zephyr:
    @echo "Fetching latest code on zephyr..."
    @parallel --tag "just-zephyr.out" -- \
        ssh $SSH_OPTS "cd ${FLAKE_PATH} && git fetch origin 2>/dev/null"
    @echo "Deploying to zephyr (with session isolation)..."
    /etc/nixos/scripts/just-cluster zephyr

nexus:
    @echo "Fetching latest code on nexus..."
    @parallel --tag "just-nexus.out" -- \
        ssh $SSH_OPTS "cd ${FLAKE_PATH} && git fetch origin 2>/dev/null"
    @echo "Deploying to nexus (with session isolation)..."
    /etc/nixos/scripts/just-cluster nexus

forge:
    @echo "Fetching latest code on forge..."
    @parallel --tag "just-forge.out" -- \
        ssh $SSH_OPTS "cd ${FLAKE_PATH} && git fetch origin 2>/dev/null"
    @echo "Deploying to forge (with session isolation)..."
    /etc/nixos/scripts/just-cluster forge

sentry:
    @echo "Skipping sentry deployment (kernel issue workaround pending)"
    # @echo "Fetching latest code on sentry..."
    # @parallel --tag "just-sentry.out" -- \
    #     ssh $SSH_OPTS "cd ${FLAKE_PATH} && git fetch origin 2>/dev/null"
    # @echo "Deploying to sentry (with session isolation)..."
    # /etc/nixos/scripts/just-cluster sentry

# Local switch for current node - runs locally with user isolation
switch:
    @echo "Switching local system configuration for user $(whoami)..."
    cd /etc/nixos && sudo -u $(id -un) -H nixos-rebuild switch --flake ".#$(hostname -s)"

# Copy age key to all nodes (run from zephyr first)
prep:
    @echo "Fetching all nodes (parallel)..."
    @parallel --tag "just-prep.{{n}}.out" -- \
        ssh $SSH_OPTS ${{HOST}} "cd ${FLAKE_PATH} && git fetch origin 2>/dev/null" & \
    ::: ::: HOST zephyr nexus forge sentry
    @wait
    @parallel --tag "just-prep-done.{{n}}.out" -- \
        echo "Prepped {{HOST}}"
        ::: ::: HOST zephyr nexus forge sentry
    @echo "Copying age key to all nodes..."
    /etc/nixos/scripts/just-cluster prep

# Deploy from current host (alternative to just-cluster)
push:
    @echo "Deploying from current host..."
    /etc/nixos/scripts/just-cluster push

# ============================================================================
# OPENCLAW SERVICE MANAGEMENT
# ============================================================================

# View OpenClaw logs
logs:
    @echo "Viewing OpenClaw gateway logs..."
    sudo journalctl -u openclaw-gateway -f

# Check OpenClaw status
status-openclaw:
    @echo "Checking OpenClaw service status..."
    sudo systemctl status openclaw-gateway
    @echo ""
    @echo "Checking health endpoint..."
    curl -sf http://localhost:18789/health || echo "Health check failed"

# Check WiVRn/Avahi status
status-vr:
    @echo "Checking Avahi daemon status..."
    sudo systemctl status avahi-daemon
    @echo ""
    @echo "Checking OpenRazer status..."
    sudo systemctl status openrazer-daemon || echo "OpenRazer may not be running"

# Restart OpenClaw
restart-openclaw:
    @echo "Restarting OpenClaw gateway..."
    sudo systemctl restart openclaw-gateway
    @echo "Waiting for service to start..."
    sleep 3
    sudo systemctl status openclaw-gateway

# Restart WiVRn services
restart-vr:
    @echo "Restarting WiVRn services..."
    sudo systemctl restart avahi-daemon
    @echo "Avahi restarted"
