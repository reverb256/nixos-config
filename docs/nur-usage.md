# NUR Usage Guide

NUR (Nix User Repository) is integrated into this NixOS configuration.

## What is NUR?

NUR is a community-driven repository of Nix packages not yet in nixpkgs.
Visit https://nur.nix-community.org/ to browse available packages.

## How to Use NUR Packages

### In Configuration Files

```nix
{ config, pkgs, inputs, ... }: {
  environment.systemPackages = with pkgs; [
    # Access NUR packages via inputs.nur.legacyPackages.x86_64-linux.repos.<username>.<package>
    inputs.nur.legacyPackages.x86_64-linux.repos.mic92.sops
  ];
}
```

### Example Packages

- `inputs.nur.legacyPackages.x86_64-linux.repos.mic92.sops` - Secret management
- `inputs.nur.legacyPackages.x86_64-linux.repos.iopq.spotify-adblock` - Spotify ad blocking
- `inputs.nur.legacyPackages.x86_64-linux.repos.sternenseemann.texlive-small` - Minimal LaTeX

### Discovery

1. Visit https://nur.nix-community.org/
2. Search for packages
3. Find the repository username and package name
4. Add to your config using the pattern above

### Updating

Update NUR along with other flake inputs:
```bash
nix flake update /etc/nixos
```

## Notes

- NUR packages are built from source (no binary cache)
- Package quality varies - check repo maintenance status
- Some packages may have long build times
- 522+ repositories currently available
