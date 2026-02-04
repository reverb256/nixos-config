# direnv Configuration Guide

This project uses direnv to provide an automated development environment with all necessary tools and configurations.

## Current Setup

The `.envrc` file is configured to:

1. **Load the Nix flake devShell** - Automatically loads all development tools defined in `flake.nix`
2. **Set useful environment variables** - Provides convenient variables for the development workflow
3. **Optimize caching** - Speeds up loading times with proper caching strategies
4. **Enhance security** - Limits what environment variables are exposed

## Environment Variables

The following environment variables are available when the environment is loaded:

- `FLAKE_ROOT` - Path to the project root
- `NIXOS_CONFIG_DIR` - Path to the NixOS configuration directory  
- `COLMENA_CONFIG` - Colmena configuration identifier
- `ZEPHYR_HOST`, `NEXUS_HOST`, `FORGE_HOST`, `SENTRY_HOST` - IP addresses of cluster hosts
- Standard Nix environment variables for caching and experimental features

## Local Overrides

Create a `.envrc.local` file to override settings locally without committing to the repository.
An example file is provided as `.envrc.local.example`.

## Security Features

- Limited environment variable exposure
- Cached environment to prevent repeated evaluations
- Properly configured whitelist for environment variables

## Caching Optimization

The environment is configured to use both the official Nix cache and your local cache at `http://192.168.100.X:9000` for faster builds.