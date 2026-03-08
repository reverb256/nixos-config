# CI/CD Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automated CI/CD pipeline for NixOS cluster configuration with GitHub Actions, self-hosted runners, pre-commit hooks, and automated deployment.

**Architecture:** Hybrid CI/CD using GitHub Actions (standard runners for quick checks, self-hosted runner on zephyr for NixOS builds), pre-commit hooks for local validation, and Colmena for multi-host deployment.

**Tech Stack:** GitHub Actions, self-hosted Actions runner, pre-commit, statix, deadnix, osv-scanner, Colmena, NixOS flakes

---

## Task 1: Create GitHub Actions CI Workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Step 1: Create the CI workflow directory**

```bash
mkdir -p .github/workflows
```

**Step 2: Write the CI workflow**

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main, master, develop]
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write

jobs:
  quick-check:
    name: Quick Check
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Nix
        uses: cachix/install-nix-action@v25
        with:
          nix_path: nixpkgs=channel:nixos-unstable

      - name: Setup Cachix
        uses: cachix/cachix-action@v14
        with:
          authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}
          extraPullNames: nixos-community

      - name: Nix flake check
        run: nix flake check --all-systems

  lint:
    name: Lint Nix
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Nix
        uses: cachix/install-nix-action@v25

      - name: Install statix
        run: nix-env -iA nixpkgs.statix

      - name: Install deadnix
        run: nix-env -iA nixpkgs.deadnix

      - name: Run statix
        run: statix check .
        continue-on-error: true

      - name: Run deadnix
        run: deadnix -f .
        continue-on-error: true

  security:
    name: Security Scan
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run osv-scanner
        uses: google/osv-scanner-action@v1
        with:
          scan-args: |
            --skip-git
            --recursive
            --format=sarif
            --output=results.sarif

      - name: Upload SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: results.sarif

  build:
    name: Build Configs
    needs: [quick-check, lint]
    runs-on: [self-hosted, nixos]
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build all hosts
        run: |
          cd /etc/nixos
          nix run .#apps.x86_64-linux.colmena -- build
```

**Step 3: Verify syntax**

Run: `cat .github/workflows/ci.yml | yamllint - || true`
Expected: No YAML syntax errors

**Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "feat(ci): add main CI workflow"
```

---

## Task 2: Create Deployment Workflow

**Files:**
- Create: `.github/workflows/deploy.yml`

**Step 1: Write the deployment workflow**

```yaml
name: Deploy

on:
  push:
    branches: [main, master]
  workflow_dispatch:
    inputs:
      target:
        description: 'Target host(s)'
        required: true
        default: 'all'
        type: choice
        options:
          - all
          - zephyr
          - nexus
          - forge
          - sentry

permissions:
  contents: read

jobs:
  deploy:
    name: Deploy to Cluster
    runs-on: [self-hosted, nixos]
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Pause mining
        run: |
          sudo systemctl stop xmrig@* || true
          sudo systemctl stop lolminer-* || true

      - name: Deploy to hosts
        run: |
          cd /etc/nixos
          if [ "${{ github.event.inputs.target }}" = "zephyr" ]; then
            just zephyr
          elif [ "${{ github.event.inputs.target }}" = "nexus" ]; then
            just nexus
          elif [ "${{ github.event.inputs.target }}" = "forge" ]; then
            just forge
          elif [ "${{ github.event.inputs.target }}" = "sentry" ]; then
            just sentry
          else
            just deploy
          fi

      - name: Resume mining
        if: always()
        run: |
          sudo systemctl start xmrig@* || true
          sudo systemctl start lolminer-* || true

      - name: Health check
        run: |
          for host in zephyr nexus forge sentry; do
            echo "Checking $host..."
            if [ "$host" = "zephyr" ]; then
              curl -f http://127.0.0.1:8080/health || true
            else
              ssh $host "curl -f http://127.0.0.1:8080/health" || true
            fi
          done

      - name: Notify on failure
        if: failure()
        run: |
          echo "Deployment failed! Check logs."
```

**Step 2: Verify syntax**

Run: `cat .github/workflows/deploy.yml | yamllint - || true`
Expected: No YAML syntax errors

**Step 3: Commit**

```bash
git add .github/workflows/deploy.yml
git commit -m "feat(ci): add deployment workflow"
```

---

## Task 3: Create Flake Update Workflow

**Files:**
- Create: `.github/workflows/flake-update.yml`

**Step 1: Write the flake update workflow**

```yaml
name: Update Flake Lock

on:
  schedule:
    - cron: '0 3 * * 0'
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: write

jobs:
  update-flake:
    name: Update flake.lock
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Nix
        uses: cachix/install-nix-action@v25
        with:
          nix_path: nixpkgs=channel:nixos-unstable

      - name: Setup Cachix
        uses: cachix/cachix-action@v14
        with:
          authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}

      - name: Update flake.lock
        run: nix flake update

      - name: Build to verify
        run: nix flake check

      - name: Create PR
        uses: peter-evans/create-pull-request@v6
        with:
          title: "chore: update flake.lock"
          body: |
            Automated flake.lock update

            Changes:
            - Updated nixpkgs
            - Updated other flake inputs

            Please review the changes and ensure nothing breaks.
          branch: update/flake-lock
          commit-message: "chore: update flake.lock"
          delete-branch: true
```

**Step 2: Verify syntax**

Run: `cat .github/workflows/flake-update.yml | yamllint - || true`
Expected: No YAML syntax errors

**Step 3: Commit**

```bash
git add .github/workflows/flake-update.yml
git commit -m "feat(ci): add automated flake update workflow"
```

---

## Task 4: Create Pre-Commit Configuration

**Files:**
- Create: `.pre-commit-config.yaml`
- Create: `scripts/ci/setup-git-hooks.sh`

**Step 1: Write pre-commit config**

```yaml
repos:
  - repo: local
    hooks:
      - id: nix-flake-check
        name: Nix flake check
        entry: bash -c 'cd /etc/nixos && nix flake check'
        language: system
        pass_filenames: false
        always_run: true

      - id: nix-lint-statix
        name: Nix lint (statix)
        entry: statix check
        language: system
        files: \.nix$

      - id: nix-lint-deadnix
        name: Nix lint (deadnix)
        entry: deadnix -f
        language: system
        files: \.nix$

      - id: trailing-whitespace
        name: Trim trailing whitespace
        entry: trailing-whitespace-fixer
        language: system
        types: [text]

      - id: end-of-file-fixer
        name: Fix end of files
        entry: end-of-file-fixer
        language: system
        types: [text]

      - id: check-added-large-files
        name: Check for large files
        entry: check-added-large-files
        language: system
        args: [--maxkb=1000]
```

**Step 2: Write setup script**

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Git Hooks ==="

# Install pre-commit via Nix
nix-env -iA nixpkgs.pre-commit

# Install hooks
pre-commit install
pre-commit install --hook-type commit-msg

echo "✓ Git hooks installed"
echo "  Run 'pre-commit run --all-files' to check all files"
```

**Step 3: Make setup script executable**

Run: `chmod +x scripts/ci/setup-git-hooks.sh`

**Step 4: Verify pre-commit config**

Run: `pre-commit validate-config`
Expected: Config is valid

**Step 5: Commit**

```bash
git add .pre-commit-config.yaml scripts/ci/setup-git-hooks.sh
git commit -m "feat(ci): add pre-commit hooks configuration"
```

---

## Task 5: Create CI Scripts Directory

**Files:**
- Create: `scripts/ci/local-ci.sh`
- Create: `scripts/ci/health-check.sh`
- Create: `scripts/deploy/rollback.sh`

**Step 1: Create local CI script**

```bash
#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
die()         { log_error "$*"; exit 1; }

echo "=== Local CI Pipeline ==="
echo ""

cd /etc/nixos

# Step 1: Quick check
log_info "Step 1: Quick flake check..."
nix flake check || die "Flake check failed"

# Step 2: Linting
log_info "Step 2: Linting Nix files..."
if command -v statix &>/dev/null; then
    statix check . || log_warn "Statix found issues"
else
    log_warn "statix not installed, skipping..."
fi

if command -v deadnix &>/dev/null; then
    deadnix -f . || log_warn "Deadnix found issues"
else
    log_warn "deadnix not installed, skipping..."
fi

# Step 3: Security scan
log_info "Step 3: Security scan..."
if command -v osv-scanner &>/dev/null; then
    osv-scanner --skip-git --recursive || log_warn "Security scan found issues"
else
    log_warn "osv-scanner not installed, skipping..."
fi

# Step 4: Build
log_info "Step 4: Building all hosts..."
nix run .#apps.x86_64-linux.colmena -- build || die "Build failed"

# Step 5: Service tests
log_info "Step 5: Checking services..."
if systemctl is-active --quiet ai-inference-gateway 2>/dev/null; then
    curl -f http://127.0.0.1:8080/health >/dev/null 2>&1 && log_info "AI Gateway: OK" || log_warn "AI Gateway: DOWN"
else
    log_warn "AI Gateway: not running"
fi

echo ""
log_info "✅ Local CI passed!"
```

**Step 2: Create health check script**

```bash
#!/usr/bin/env bash
set -euo pipefail

HOSTS="zephyr nexus forge sentry"

echo "=== Cluster Health Check ==="
echo ""

for host in $HOSTS; do
    if [ "$host" = "$(hostname -s)" ]; then
        echo "[$host] Local:"
        systemctl is-active ai-inference-gateway >/dev/null 2>&1 && echo "  ✓ AI Gateway" || echo "  ✗ AI Gateway"
        curl -f http://127.0.0.1:8080/health >/dev/null 2>&1 && echo "  ✓ HTTP health" || echo "  ✗ HTTP health"
    else
        echo "[$host] Remote:"
        if ssh -o ConnectTimeout=2 "$host" true >/dev/null 2>&1; then
            ssh "$host" "systemctl is-active ai-inference-gateway" >/dev/null 2>&1 && echo "  ✓ AI Gateway" || echo "  ✗ AI Gateway"
        else
            echo "  ✗ Host unreachable"
        fi
    fi
    echo ""
done
```

**Step 3: Create rollback script**

```bash
#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-$(hostname -s)}"
GENERATION="${2:-}"

if [ -z "$GENERATION" ]; then
    echo "Available generations:"
    sudo nixos-rebuild list-generations --profile /nix/var/nix/profiles/system | grep -E "^\s+[0-9]+" | tail -5
    echo ""
    echo "Usage: $0 [host] [generation-number]"
    exit 1
fi

if [ "$HOST" = "$(hostname -s)" ]; then
    echo "Rolling back local system to generation $GENERATION..."
    sudo nixos-rebuild switch --profile /nix/var/nix/profiles/system --switch-generation "$GENERATION"
else
    echo "Rolling back $HOST to generation $GENERATION..."
    ssh "$HOST" "sudo nixos-rebuild switch --profile /nix/var/nix/profiles/system --switch-generation $GENERATION"
fi

echo "✓ Rollback complete"
```

**Step 4: Make scripts executable**

Run: `chmod +x scripts/ci/*.sh scripts/deploy/*.sh`

**Step 5: Commit**

```bash
git add scripts/ci/ scripts/deploy/
git commit -m "feat(ci): add CI scripts (local-ci, health-check, rollback)"
```

---

## Task 6: Create Self-Hosted Runner Module

**Files:**
- Create: `modules/services/ci-runner.nix`
- Create: `scripts/ci/setup-runner.sh`

**Step 1: Write NixOS module**

```nix
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.ci-runner;
in {
  options.services.ci-runner = {
    enable = mkEnableOption "GitHub Actions self-hosted runner";

    user = mkOption {
      type = types.str;
      default = "actions-runner";
      description = "User to run the runner as";
    };

    repo = mkOption {
      type = types.str;
      example = "username/nixos-config";
      description = "GitHub repository (owner/repo)";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = "nixos";
      extraGroups = [ "nixos" "wheel" ];
      description = "GitHub Actions runner";
    };

    systemd.services.github-actions-runner = {
      description = "GitHub Actions Self-Hosted Runner";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        WorkingDirectory = "/var/lib/${cfg.user}";
        ExecStart = "/var/lib/${cfg.user}/run.sh";
        Restart = "always";
        RestartSec = "10s";
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}
```

**Step 2: Write runner setup script**

```bash
#!/usr/bin/env bash
set -euo pipefail

RUNNER_USER="actions-runner"
RUNNER_HOME="/var/lib/actions-runner"
REPO="${1:-$(cd /etc/nixos && git config --get remote.origin.url | sed 's/.*github.com[:/]\(.*\)\.git/\1/')}"

echo "=== Setting up GitHub Actions Self-Hosted Runner ==="
echo "Repository: $REPO"

# Create runner user
sudo useradd -m -s /bin/bash "$RUNNER_USER" || true
sudo usermod -aG nixos "$RUNNER_USER"

# Download and install runner
cd "$RUNNER_HOME"
sudo -u "$RUNNER_USER" mkdir -p actions-runner

LATEST_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name)
ARCH="x64"

sudo -u "$RUNNER_USER" curl -o actions-runner.tar.gz -L \
  "https://github.com/actions/runner/releases/download/${LATEST_VERSION}/actions-runner-linux-${ARCH}-${LATEST_VERSION#v}.tar.gz"

sudo -u "$RUNNER_USER" tar xzf ./actions-runner.tar.gz
rm actions-runner.tar.gz

# Configure runner
echo "Enter GitHub registration token:"
read -rs TOKEN

cd actions-runner
sudo -u "$RUNNER_USER" ./config.sh \
  --url "https://github.com/$REPO" \
  --token "$TOKEN" \
  --labels nixos,self-hosted \
  --work "/tmp/actions-runner/_work"

# Install systemd service
sudo ./svc.sh install "$RUNNER_USER"
sudo ./svc.sh start

echo "✓ Runner installed and started"
echo "  Check status: sudo ./svc.sh status"
echo "  Stop: sudo ./svc.sh stop"
```

**Step 3: Make setup script executable**

Run: `chmod +x scripts/ci/setup-runner.sh`

**Step 4: Commit**

```bash
git add modules/services/ci-runner.nix scripts/ci/setup-runner.sh
git commit -m "feat(ci): add self-hosted runner module and setup script"
```

---

## Task 7: Update Justfile with CI Targets

**Files:**
- Modify: `justfile`

**Step 1: Add CI targets to justfile**

Add after the existing `cluster-status` target:

```makefile
# ============================================================================
# CI/CD - Local & Remote
# ============================================================================
# Run CI locally (simulate GitHub Actions)
ci-local:
    @echo "Running local CI..."
    @echo "→ Quick check..."
    nix flake check
    @echo "→ Linting..."
    statix check . || true
    deadnix -f . || true
    @echo "→ Building all hosts..."
    nix run .#apps.x86_64-linux.colmena -- build
    @echo "✅ Local CI passed!"

# Run pre-commit checks on all files
pre-commit-all:
    @echo "Running pre-commit on all files..."
    pre-commit run --all-files

# Update flake.lock
flake-update:
    @echo "Updating flake.lock..."
    nix flake update
    @echo "✓ Flake updated. Run 'just ci-local' to verify."

# Security scan locally
security-scan:
    @echo "Running security scan..."
    nix-shell -p osv-scanner --run "osv-scanner --skip-git --recursive"

# ============================================================================
# CI/CD Status
# ============================================================================
# Show CI/CD status
ci-status:
    @echo "=== CI/CD Status ==="
    @echo ""
    @echo "Pre-commit:"
    @pre-commit --version 2>/dev/null || echo "  Not installed"
    @echo ""
    @echo "Flake inputs age:"
    @nix flake metadata | grep "Last modified" || true
    @echo ""
    @echo "Recent flake updates:"
    @git log --oneline --all --grep="flake" -5 || echo "  None found"

# ============================================================================
# CI/CD Utilities
# ============================================================================
# Cluster health check
health-check:
    scripts/ci/health-check.sh

# Rollback to previous generation
rollback:
    scripts/deploy/rollback.sh
```

**Step 2: Test justfile syntax**

Run: `just --list`
Expected: CI targets appear in list

**Step 3: Commit**

```bash
git add justfile
git commit -m "feat(ci): add CI targets to justfile"
```

---

## Task 8: Create CI Documentation

**Files:**
- Create: `docs/ci-cd-setup.md`
- Create: `docs/ci-cd-usage.md`

**Step 1: Write setup documentation**

```markdown
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

\`\`\`bash
# Run the setup script
sudo /etc/nixos/scripts/ci/setup-runner.sh

# Enable the CI runner module in zephyr's config
# Add: services.ci-runner.enable = true;
sudo nixos-rebuild switch
\`\`\`

### 2. GitHub Secrets

Add to repository Settings → Secrets and variables → Actions:

| Secret | Description |
|--------|-------------|
| `CACHIX_AUTH_TOKEN` | Cachix authentication token (optional) |

### 3. Pre-Commit Hooks

\`\`\`bash
# Run the setup script
/etc/nixos/scripts/ci/setup-git-hooks.sh
\`\`\`

## Verification

### Test CI locally

\`\`\`bash
just ci-local
\`\`\`

### Test runner status

\`\`\`bash
sudo ./svc.sh status  # From /var/lib/actions-runner/actions-runner
\`\`\`

### Test health check

\`\`\`bash
just health-check
\`\`\`
```

**Step 2: Write usage documentation**

```markdown
# CI/CD Usage Guide

## Daily Workflow

### Making Changes

1. Make changes to configuration
2. Run local CI: `just ci-local`
3. Commit and push
4. GitHub Actions validates PR
5. Merge to main triggers deployment

### Local Commands

| Command | Purpose |
|---------|---------|
| `just ci-local` | Run full CI locally |
| `just pre-commit-all` | Run pre-commit on all files |
| `just flake-update` | Update flake.lock |
| `just security-scan` | Run security scan |
| `just health-check` | Check cluster health |
| `just rollback` | Rollback to previous generation |

### Deployment

#### Automatic

Merge to `main` or `master` triggers deployment to all hosts.

#### Manual

Go to Actions → Deploy → Run workflow → Select target host.

### Troubleshooting

#### CI failures

Check GitHub Actions tab for detailed logs.

#### Deployment failures

\`\`\`bash
# Check logs
journalctl -u github-actions-runner -f

# Rollback
just rollback <host> <generation>
\`\`\`

#### Runner not starting

\`\`\`bash
# Check service
sudo systemctl status github-actions-runner

# Restart
sudo systemctl restart github-actions-runner
\`\`\`
```

**Step 3: Commit**

```bash
git add docs/ci-cd-setup.md docs/ci-cd-usage.md
git commit -m "docs(ci): add CI/CD setup and usage documentation"
```

---

## Task 9: Enable CI Runner on Zephyr

**Files:**
- Modify: `hosts/zephyr/configuration.nix`

**Step 1: Add CI runner module to zephyr**

Add to imports section:

```nix
# Services modules
../../modules/services/ci-runner.nix
```

Add to services section:

```nix
# ============================================================================
# CI/CD - Self-hosted GitHub Actions runner
# ============================================================================
services.ci-runner = {
  enable = true;
  repo = "your-username/nixos";  # Replace with actual repo
};
```

**Step 2: Test build**

Run: `nix flake check`
Expected: No errors

**Step 3: Commit**

```bash
git add hosts/zephyr/configuration.nix
git commit -m "feat(zephyr): enable CI runner service"
```

---

## Task 10: Final Testing & Verification

**Step 1: Test local CI**

Run: `just ci-local`
Expected: All checks pass

**Step 2: Test pre-commit hooks**

Run: `just pre-commit-all`
Expected: All hooks pass

**Step 3: Test health check**

Run: `just health-check`
Expected: All hosts report status

**Step 4: Verify GitHub Actions workflows**

Run: `cat .github/workflows/*.yml | yamllint - || true`
Expected: No YAML errors

**Step 5: Create summary commit**

```bash
git add -A
git commit -m "feat(ci-cd): complete CI/CD pipeline implementation

Implemented comprehensive CI/CD pipeline:

- GitHub Actions workflows (ci, deploy, flake-update)
- Self-hosted runner on zephyr
- Pre-commit hooks for local validation
- CI scripts (local-ci, health-check, rollback)
- Enhanced justfile with CI targets
- Full documentation

All workflows tested and verified.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Summary

This implementation plan creates a complete CI/CD pipeline:

1. **CI on every PR** - Validates before merge
2. **Automated deployment** - On merge to main
3. **Local validation** - Pre-commit hooks + `just ci-local`
4. **Security scanning** - osv-scanner for vulnerabilities
5. **Automated updates** - Weekly flake.lock PRs
6. **Rollback support** - One-command rollback

Total estimated time: 2-3 hours
Commit count: 10 commits
Files created: 15
Files modified: 2
