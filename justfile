# NixOS Cluster Deployment
# Deploys to zephyr, nexus, forge, sentry via SSH

_default:
    @echo "NixOS Cluster Management"
    @echo ""
    @echo "USAGE:"
    @echo "  just build         Build configs (dry run)"
    @echo "  just deploy        Deploy to all hosts"
    @echo "  just zephyr        Deploy to zephyr"
    @echo "  just nexus         Deploy to nexus"
    @echo "  just forge         Deploy to forge"
    @echo "  just sentry        Deploy to sentry"
    @echo "  just switch        Local switch (zephyr)"
    @echo "  just update        Update flake + deploy"

# Build all configurations (dry run)
build:
    sudo /etc/nixos/scripts/colmena-deploy build

# Deploy to all cluster hosts
deploy:
    sudo /etc/nixos/scripts/colmena-deploy deploy

# Deploy to individual hosts
zephyr:
    sudo /etc/nixos/scripts/colmena-deploy zephyr

nexus:
    sudo /etc/nixos/scripts/colmena-deploy nexus

forge:
    sudo /etc/nixos/scripts/colmena-deploy forge

sentry:
    sudo /etc/nixos/scripts/colmena-deploy sentry

# Local switch for zephyr
switch:
    sudo nixos-rebuild switch --flake ".#zephyr"

# Update flake and deploy
update:
    @cd /etc/nixos && git pull origin main
    nix flake update
    just deploy

# CI status
ci:
    @gh run list --repo reverb256/nixos-config --limit 1

# Cluster info
status:
    @echo "=== CLUSTER ==="
    @echo "zephyr: 10.1.1.110 (local)"
    @echo "nexus:   10.1.1.120"
    @echo "forge:   10.1.1.130"
    @echo "sentry:  10.1.1.140"
