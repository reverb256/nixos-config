# Dendritic Modules

This directory contains the hierarchical, composable modules for the Reverb-OS NixOS cluster using flake-parts architecture.

## Directory Structure

```
dendritic-modules/
├── core/           # Core NixOS configuration
├── desktop/        # Desktop environment modules
├── compute/        # Compute/GPU modules
├── services/       # Service modules
├── profiles/       # Host profiles (composable)
└── hosts/          # Host-specific modules
```

## Usage

These modules are imported via flake-parts in the main `flake.nix` file.

## Migration Notes

- This structure replaces the monolithic `modules/default.nix` approach
- Each subdirectory contains related, focused modules
- Profiles allow composable host configurations
- Redundant imports have been eliminated
