# NixOS Configuration Justfile
# Run `just` to see available commands

default:
    @just --list

# Check configuration syntax (no build)
check:
    nix flake check

# Update all flake inputs
update:
    nix flake update

# Show available configurations
show:
    nix flake show

# Build configuration (dry-run, no system modification)
build:
    sudo nixos-rebuild build --flake .#zephyr

# Test configuration (applies changes, rollback on next boot)
test:
    sudo nixos-rebuild test --flake .#zephyr

# Switch to new configuration (persist across reboots)
switch:
    sudo nixos-rebuild switch --flake .#zephyr

# Format all .nix files
fmt:
    nix-shell -p nixpkgs-fmt --run "nixpkgs-fmt **/*.nix"

# Format specific files
fmt-files files:
    nixpkgs-fmt {{files}}

# Run update, check, and build in sequence
verify: update check build

# Show current git status
status:
    @git status

# Commit changes with message
commit message:
    git add .
    git commit -m "{{message}}"

# Clean up old generations (keeps last 5)
clean:
    sudo nix-collect-garbage -d

# Garbage collect and optimize store
gc:
    sudo nix-collect-garbage --delete-old
    sudo nix-store --optimize

# Rebuild hardware configuration (DO NOT EDIT hardware-configuration.nix)
regenerate-hardware:
    sudo nixos-generate-config --root /mnt

# Help message
help:
    @echo "Common workflow:"
    @echo "  1. make changes to configuration"
    @echo "  2. just fmt           # format files"
    @echo "  3. just check         # validate syntax"
    @echo "  4. just verify        # update, check, and build"
    @echo "  5. just test          # test configuration"
    @echo "  6. just switch        # apply permanently"
