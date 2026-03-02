# NixOS Configuration - Agent Guidelines

## Project Overview
This is a NixOS flake-based system configuration for host "zephyr" running Plasma 6 desktop.
All system configurations are declarative and managed through Nix modules.

---

## Build & Test Commands

### Essential Commands
```bash
# Build configuration (dry-run, no system modification)
sudo nixos-rebuild build --flake .#zephyr

# Test configuration (applies changes, rollback on next boot)
sudo nixos-rebuild test --flake .#zephyr

# Switch to new configuration (persist across reboots)
sudo nixos-rebuild switch --flake .#zephyr

# Update all flake inputs
nix flake update

# Check configuration syntax (no build)
nix flake check
```

### Testing Strategy
1. Always run `nix flake check` first for syntax validation
2. Use `nixos-rebuild build` to verify configuration compiles
3. Use `nixos-rebuild test` for temporary changes (rollback safe)
4. Only use `switch` for verified, production-ready changes

---

## Code Style Guidelines

### Nix Language Conventions
- **2 spaces** for indentation (no tabs)
- Blank lines between major sections
- Comments use `#` prefix, place above setting not inline

### Attribute Sets & Lists
```nix
{ config, pkgs, inputs, ... }:  # Use ellipsis pattern
{
  description = "NixOS configuration";
  inputs = { inherit nixpkgs home-manager; };  # Use inherit
};
```

### Lists
```nix
environment.systemPackages = with pkgs; [
  tmux
  mosh
  tailscale
  inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
];
```

---

## Project Structure

### Files
- **flake.nix**: Inputs and outputs (EDIT THIS)
- **configuration.nix**: Main system config (EDIT THIS)
- **hardware-configuration.nix**: Auto-generated (DO NOT EDIT)
- **flake.lock**: Reproducibility lockfile (AUTO-GENERATED, DO NOT EDIT)

### Adding Configurations
- System settings → `configuration.nix`
- User settings → `home-manager.users.j_kro` block
- New flake inputs → `inputs` in flake.nix, pass via `specialArgs`

---

## Naming Conventions
- Hostnames: lowercase (e.g., `zephyr`)
- Usernames: underscores for spaces (e.g., `j_kro`)
- Flake inputs: lowercase with hyphens (e.g., `zen-browser`)
- Service names: match systemd services (e.g., `tailscale`, `networkmanager`)

---

## Formatting
```bash
# Format all .nix files
nix-shell -p nixpkgs-fmt --run "nixpkgs-fmt **/*.nix"

# Format specific files
nixpkgs-fmt flake.nix configuration.nix
```

---

## Common Patterns
```nix
# Enable services
services.xserver.enable = true;
services.desktopManager.plasma6.enable = true;

# System packages
environment.systemPackages = with pkgs; [ package1 package2 ];

# User config
users.users.j_kro = {
  isNormalUser = true;
  description = "Jeremy Kroeker";
  shell = pkgs.fish;
  extraGroups = [ "networkmanager" "wheel" ];
};

# Home Manager
home-manager.users.j_kro = { pkgs, lib, ... }: {
  home.stateVersion = "26.05";
};
```

---

## Important Notes
- Keep `system.stateVersion` and `home.stateVersion` current
- Never edit `hardware-configuration.nix` - regenerate with `nixos-generate-config`
- Run `nix flake update` before making changes
- Check `nix flake show` for available configurations
- Build/test/switch require root/sudo
