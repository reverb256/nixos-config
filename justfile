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
    sudo nix shell .#colmena -- colmena build -f /etc/nixos/hive.nix

# Deploy to all cluster hosts
deploy:
    @cd /etc/nixos && git pull origin main
    sudo nix shell .#colmena -- colmena apply -f /etc/nixos/hive.nix --on '@default'

# Deploy to individual hosts
zephyr:
    sudo nix shell .#colmena -- colmena apply -f /etc/nixos/hive.nix --on 'zephyr'

nexus:
    sudo nix shell .#colmena -- colmena apply -f /etc/nixos/hive.nix --on 'nexus'

forge:
    sudo nix shell .#colmena -- colmena apply -f /etc/nixos/hive.nix --on 'forge'

sentry:
    sudo nix shell .#colmena -- colmena apply -f /etc/nixos/hive.nix --on 'sentry'

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
