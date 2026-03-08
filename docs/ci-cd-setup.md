# CI/CD Setup Guide

## Overview

This cluster uses GitHub Actions for CI/CD with a self-hosted runner on zephyr.

## Prerequisites

- GitHub repository access
- Admin access to zephyr
- GitHub Personal Access Token (for runner registration)

## Setup Steps

### 1. Self-Hosted Runner

On zephyr:

```bash
# Run the setup script
sudo /etc/nixos/scripts/ci/setup-runner.sh

# Enable the CI runner module in zephyr's config
# Add: services.ci-runner.enable = true;
sudo nixos-rebuild switch
```

### 2. GitHub Secrets

Add to repository Settings -> Secrets and variables -> Actions:

| Secret | Description |
|--------|-------------|
| `CACHIX_AUTH_TOKEN` | Cachix authentication token (optional) |

### 3. Pre-Commit Hooks

```bash
# Run the setup script
/etc/nixos/scripts/ci/setup-git-hooks.sh
```

## Verification

### Test CI locally

```bash
just ci-local
```

### Test runner status

```bash
sudo ./svc.sh status  # From /var/lib/actions-runner/actions-runner
```

### Test health check

```bash
just health-check
```
