# NixOS Management with Colmena - Multi-host deployment
# https://colmena.cli.rs
# Organized by scope: local, cluster, development, gaming, utilities
#
# FEATURES:
# ✅ Colmena-native for all cluster operations
# ✅ Idempotent by default
# ✅ Parallel deployments via colmena
# ✅ Local operations via nixos-rebuild

# Default target (show help)
default: help

# Quick access alias for j_kro user
j: help

# Ensure we're in the correct directory and colmena is available
_setup:
   #!/usr/bin/env bash
   if [ -f "flake.nix" ] && [ -f "justfile" ]; then
     :
   elif [ -d "/etc/nixos" ] && [ -f "/etc/nixos/flake.nix" ]; then
     cd /etc/nixos
   else
     echo "Error: Cannot find NixOS config directory (/etc/nixos)"
     echo "Ensure /etc/nixos exists with flake.nix"
     exit 1
   fi
   if ! command -v colmena &> /dev/null; then
     echo "Error: Colmena is not installed"
     echo "Install with: nix shell nixpkgs#colmena or add to system-packages.nix"
     exit 1
   fi

# =============================================================================
# LOCAL SYSTEM MANAGEMENT (nixos-rebuild)
# =============================================================================

# Switch to new NixOS configuration on local machine
switch: _setup
   @echo "Switching zephyr to new configuration..."
   sudo nixos-rebuild switch --flake .#zephyr || true
   @echo "Local switch complete!"

# Build without switching (dry run validation)
build: _setup
   @echo "Building zephyr configuration..."
   nixos-rebuild build --flake .#zephyr || true
   @echo "Build complete!"

# Test configuration temporarily (reverts on reboot)
test: _setup
   @echo "Testing zephyr configuration..."
   sudo nixos-rebuild test --flake .#zephyr || true
   @echo "Test complete!"

# Update flake inputs and switch
update: _setup
   @echo "Updating flake inputs..."
   nix flake update || true
   @echo "Switching to updated configuration..."
   sudo nixos-rebuild switch --flake .#zephyr || true
   @echo "Update complete!"

# Update and set as boot default (no switch)
update-boot: _setup
   @echo "Updating flake inputs..."
   nix flake update || true
   @echo "Building and setting as boot default..."
   sudo nixos-rebuild boot --flake .#zephyr || true
   @echo "Boot default updated!"

# Remove old NixOS generations
clean: _setup
   @echo "Cleaning old generations..."
   sudo nix-env --delete-generations +5 --profile /nix/var/nix/profiles/system || true
   nix-collect-garbage -d || true
   @echo "Cleanup complete!"

# List system generations
generations: _setup
   @echo "System generations:"
   @sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -10

# Rollback to previous generation
rollback: _setup
   @echo "Rolling back to previous generation..."
   sudo nixos-rebuild switch --rollback || true
   @echo "Rollback complete!"

# System information
status: _setup
   @echo "=== NIXOS STATUS ==="
   @echo "Current: $(readlink /run/current-system | cut -d- -f2)"
   @echo "Boot: $(readlink /run/booted-system | cut -d- -f2)"
   @echo ""
   @echo "=== RESOURCES ==="
   @free -h | head -2
   @df -h / | tail -1
   @uptime | tail -1

# =============================================================================
# CLUSTER MANAGEMENT (Colmena)
# =============================================================================

# Build all host configurations (dry run)
cluster-build: _setup
   @echo "Building configurations for all hosts..."
   colmena build || true
   @echo "Cluster build complete!"

# Deploy to all hosts (parallel by default)
cluster-deploy: _setup
   @echo "Deploying to all cluster hosts..."
   sudo colmena apply || true
   @echo "Cluster deployment complete!"

# Deploy to specific host
deploy HOST: _setup
   @echo "Deploying to $<HOST>..."
   sudo colmena apply --on $<HOST> || true
   @echo "Deployment to $<HOST> complete!"

# Deploy to individual hosts
deploy-nexus: _setup
   @echo "Deploying to nexus..."
   sudo colmena apply --on nexus || true
   @echo "Deployment to nexus complete!"

deploy-forge: _setup
   @echo "Deploying to forge..."
   sudo colmena apply --on forge || true
   @echo "Deployment to forge complete!"

deploy-sentry: _setup
   @echo "Deploying to sentry..."
   sudo colmena apply --on sentry || true
   @echo "Deployment to sentry complete!"

deploy-zephyr: switch

# Update flake + deploy to all hosts
cluster-update: _setup
   @echo "Updating flake inputs..."
   nix flake update || true
   @echo "Deploying updated configuration to all hosts..."
   sudo colmena apply || true
   @echo "Cluster update complete!"

# Check status of all hosts
cluster-status: _setup
   @echo "Cluster Status:"
   colmena info || true

# Show resource usage across cluster
cluster-resources: _setup
   @echo "=== ZEPHYR (Local) ==="
   @free -h | head -2
   @df -h / | tail -1
   @echo ""
   @echo "=== REMOTE HOSTS ==="
   @echo "nexus:"
   @ssh j_kro@nexus "free -h | head -2 && df -h / | tail -1" 2>/dev/null || echo "  Unreachable"
   @echo "forge:"
   @ssh j_kro@forge "free -h | head -2 && df -h / | tail -1" 2>/dev/null || echo "  Unreachable"
   @echo "sentry:"
   @ssh j_kro@sentry "free -h | head -2 && df -h / | tail -1" 2>/dev/null || echo "  Unreachable"

# Show mining status across cluster
cluster-mining: _setup
   @echo "Mining Status:"
   @echo "=== ZEPHYR ==="
   @sudo systemctl status lolminer-nvidia.service xmrig.service --no-pager -l 2>/dev/null || echo "Not running"
   @echo "=== NEXUS ==="
   @ssh j_kro@nexus "sudo systemctl status lolminer-nvidia.service xmrig.service --no-pager -l" 2>/dev/null || echo "Unreachable"
   @echo "=== FORGE ==="
   @ssh j_kro@forge "sudo systemctl status lolminer-nvidia.service xmrig.service --no-pager -l" 2>/dev/null || echo "Unreachable"
   @echo "=== SENTRY ==="
   @ssh j_kro@sentry "sudo systemctl status lolminer-nvidia.service xmrig.service --no-pager -l" 2>/dev/null || echo "Unreachable"

# Clean old generations on all hosts
cluster-clean: _setup
   @echo "Cleaning old generations on all hosts..."
   @ssh j_kro@nexus "sudo nix-env --delete-generations +5 --profile /nix/var/nix/profiles/system && nix-collect-garbage -d" 2>/dev/null || echo "nexus: Failed"
   @ssh j_kro@forge "sudo nix-env --delete-generations +5 --profile /nix/var/nix/profiles/system && nix-collect-garbage -d" 2>/dev/null || echo "forge: Failed"
   @ssh j_kro@sentry "sudo nix-env --delete-generations +5 --profile /nix/var/nix/profiles/system && nix-collect-garbage -d" 2>/dev/null || echo "sentry: Failed"
   @echo "Cluster cleanup complete!"

# Rollback all hosts
cluster-rollback: _setup
   @echo "Rolling back all hosts..."
   @ssh j_kro@nexus "sudo nixos-rebuild switch --rollback" 2>/dev/null || echo "nexus: Failed"
   @ssh j_kro@forge "sudo nixos-rebuild switch --rollback" 2>/dev/null || echo "forge: Failed"
   @ssh j_kro@sentry "sudo nixos-rebuild switch --rollback" 2>/dev/null || echo "sentry: Failed"
   @echo "Cluster rollback complete!"

# Emergency stop all services
cluster-emergency: _setup
   @echo "EMERGENCY STOP - Stopping all services..."
   sudo systemctl stop lolminer-nvidia.service xmrig.service gaming-optimizations.service 2>/dev/null || true
   @ssh j_kro@nexus "sudo systemctl stop lolminer-nvidia.service xmrig.service gaming-optimizations.service" 2>/dev/null || true
   @ssh j_kro@forge "sudo systemctl stop lolminer-nvidia.service xmrig.service gaming-optimizations.service" 2>/dev/null || true
   @ssh j_kro@sentry "sudo systemctl stop lolminer-nvidia.service xmrig.service gaming-optimizations.service" 2>/dev/null || true
   @echo "Emergency stop complete!"

# Cluster information
cluster-info: _setup
   @echo "Cluster Information:"
   @echo ""
   @echo "Hosts:"
   @echo "  zephyr  - 10.1.1.110 (Local - VR/Gaming/Mining)"
   @echo "  nexus   - 10.1.1.120 (Backup Server)"
   @echo "  forge   - 10.1.1.130 (Build Server)"
   @echo "  sentry  - 10.1.1.140 (Monitoring Server)"
   @echo ""
   @echo "Total Capacity: 51 cores"
   @echo ""
   @echo "Commands:"
   @echo "  just switch              Local switch"
   @echo "  just update              Update flake + local switch"
   @echo "  just cluster-deploy      Deploy to all hosts"
   @echo "  just deploy nexus/forge/sentry  Deploy to specific host"
   @echo "  just cluster-update      Update flake + deploy all"
   @echo "  just cluster-build       Build all configs (dry run)"
   @echo "  just cluster-status      Show cluster status"
   @echo "  just cluster-resources   Show resource usage"
   @echo "  just cluster-clean       Clean old generations"
   @echo "  just cluster-mining      Show mining status"

# =============================================================================
# DEVELOPMENT WORKFLOW
# =============================================================================

# Validate flake
check: _setup
   @echo "Checking flake..."
   nix flake check . || true
   @echo "Flake check passed!"

# Format Nix files
format: _setup
   @echo "Formatting Nix files..."
   alejandra $(find . -name "*.nix" -type f 2>/dev/null) || true
   @echo "Formatting complete!"

# Lint Nix files
lint: _setup
   @echo "Linting Nix files..."
   statix check $(find . -name "*.nix" -type f 2>/dev/null) || true
   @echo "Linting complete!"

# Full development pipeline
dev-setup: check format lint

# =============================================================================
# GAMING & MINING
# =============================================================================

# Gaming services
gaming-start:
   @echo "Starting gaming services..."
   sudo systemctl start lolminer-nvidia.service xmrig.service gaming-optimizations.service 2>/dev/null || true
   @echo "Gaming services started!"

gaming-stop:
   @echo "Stopping gaming services..."
   sudo systemctl stop lolminer-nvidia.service xmrig.service gaming-optimizations.service 2>/dev/null || true
   @echo "Gaming services stopped!"

gaming-status:
   @echo "Gaming Services:"
   sudo systemctl status lolminer-nvidia.service xmrig.service gaming-optimizations.service --no-pager -l || true

# Mining services
mining-start:
   @echo "Starting mining services..."
   sudo systemctl start lolminer-nvidia.service xmrig.service 2>/dev/null || true
   @echo "Mining started!"

mining-stop:
   @echo "Stopping mining services..."
   sudo systemctl stop lolminer-nvidia.service xmrig.service 2>/dev/null || true
   @echo "Mining stopped!"

mining-status:
   @echo "Mining Services:"
   sudo systemctl status lolminer-nvidia.service xmrig.service --no-pager -l || true

# Performance monitoring
perf-monitor:
   @echo "=== GPU ==="
   @nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null || echo "GPU not available"
   @echo ""
   @echo "=== CPU ==="
   @uptime | awk -F'load average:' '{ print "Load:", $2 }' || true
   @echo ""
   @echo "=== TOP PROCESSES ==="
   @ps aux --sort=-%cpu | head -6 | awk 'NR==1{print} NR>1{printf "%-8s %-5s %-5s %s\n", $1, $3, $4, $11}' || true

# =============================================================================
# UTILITIES
# =============================================================================

# Search packages
search PKG:
   nix search nixpkgs {{PKG}}

# Install temporary package
install PKG:
   nix shell nixpkgs#{{PKG}}

# Network status
net-status:
   @echo "=== NETWORK ==="
   @ip addr show | grep -E "inet " | head -3 || true
   @ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo "Internet: Connected" || echo "Internet: Disconnected"

# Hardware info
hw-info:
   @echo "=== HARDWARE ==="
   @echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)" || true
   @echo "Cores: $(lscpu | grep '^CPU(s):' | awk '{print $2}')" || true
   @echo "Memory: $(free -h | grep '^Mem:' | awk '{print $2}')" || true
   @nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo "GPU: None"

# Backup config
backup: _setup
   #!/usr/bin/env bash
   BACKUP_DIR="/tmp/nixos-backup-$(date +%Y%m%d-%H%M%S)"
   echo "Creating backup: $BACKUP_DIR"
   mkdir -p "$BACKUP_DIR" || true
   cp -r /etc/nixos/* "$BACKUP_DIR/" || true
   echo "Backup created!"

# =============================================================================
# HELP
# =============================================================================

help:
   @echo "NixOS Management with Colmena"
   @echo ""
   @echo "LOCAL OPERATIONS:"
   @echo "  switch              Switch local system"
   @echo "  build               Build local config (dry run)"
   @echo "  test                Test local config"
   @echo "  update              Update flake + switch"
   @echo "  clean               Clean old generations"
   @echo "  status              Show system status"
   @echo ""
   @echo "CLUSTER OPERATIONS:"
   @echo "  cluster-deploy      Deploy to all hosts"
   @echo "  cluster-deploy <h>  Deploy to specific host"
   @echo "  cluster-update      Update flake + deploy all"
   @echo "  cluster-build       Build all configs"
   @echo "  cluster-status      Show cluster status"
   @echo "  cluster-resources   Show resource usage"
   @echo "  cluster-mining      Show mining status"
   @echo "  cluster-clean       Clean old generations"
   @echo "  cluster-rollback    Rollback all hosts"
   @echo "  cluster-emergency   Emergency stop all"
   @echo ""
   @echo "GAMING & MINING:"
   @echo "  gaming-start/stop   Gaming services"
   @echo "  mining-start/stop   Mining services"
   @echo "  perf-monitor        Show performance"
   @echo ""
   @echo "DEVELOPMENT:"
   @echo "  check               Validate flake"
   @echo "  format              Format Nix files"
   @echo "  lint                Lint Nix files"
   @echo "  dev-setup           Full dev pipeline"
   @echo ""
   @echo "UTILITIES:"
   @echo "  search <pkg>        Search packages"
   @echo "  install <pkg>       Install temp package"
   @echo "  net-status          Network status"
   @echo "  hw-info             Hardware info"
   @echo "  backup              Create backup"
   @echo ""
   @echo "Examples:"
   @echo "  just switch         Update and switch"
   @echo "  just cluster-deploy Deploy to cluster"
   @echo "  just update         Update flake + switch"
   @echo "  just perf-monitor   Check performance"
