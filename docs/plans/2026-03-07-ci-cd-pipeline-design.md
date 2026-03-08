# CI/CD Pipeline Design - NixOS Cluster

**Date:** 2026-03-07
**Author:** Claude Opus 4.6
**Status:** Approved
**Branch:** `feature/ci-cd-pipeline`

## Overview

Comprehensive CI/CD pipeline for the NixOS cluster configuration, combining GitHub Actions (SaaS) with self-hosted runners for native NixOS builds. The pipeline provides automated testing, linting, security scanning, and deployment across the cluster (zephyr, nexus, forge, sentry).

## Problem Statement

- **No CI/CD**: Zero automated validation on push/PR
- **Manual deployments**: `just deploy` requires manual execution
- **No security scanning**: Dependencies unchecked for vulnerabilities
- **No flake lock automation**: Manual dependency updates
- **Broken configs possible**: Can merge changes that fail to build
- **No pre-commit validation**: Developers can commit malformed Nix

## Solution

Hybrid CI/CD approach:
1. **GitHub Actions (standard runners)**: Quick validation, linting, security scanning
2. **Self-hosted runner (zephyr)**: Native NixOS builds, Colmena integration
3. **Pre-commit hooks**: Local validation before commit
4. **Automated flake updates**: Weekly PRs for dependency updates
5. **Deployment automation**: Manual trigger + auto-deploy on merge to main

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         GitHub Repository                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Push/PR                    CI/CD Pipeline                              │
│    │                        │                                            │
│    ▼                        ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                   GitHub Actions Workflow                        │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │                                                                  │   │
│  │  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐         │   │
│  │  │   Quick      │   │    Lint      │   │  Security    │         │   │
│  │  │   Check      │──▶│    Nix       │──▶│   Scan       │         │   │
│  │  │ (ubuntu-     │   │  (statix/    │   │  (osv-       │         │   │
│  │  │  latest)     │   │   deadnix)   │   │   scanner)   │         │   │
│  │  └──────────────┘   └──────────────┘   └──────────────┘         │   │
│  │                                                                  │   │
│  │                              ▼                                   │   │
│  │                     ┌──────────────────┐                        │   │
│  │                     │  Self-Hosted     │                        │   │
│  │                     │  Runner (zephyr) │                        │   │
│  │                     ├──────────────────┤                        │   │
│  │                     │ • nix flake     │                        │   │
│  │                     │   check         │                        │   │
│  │                     │ • colmena build │                        │   │
│  │                     │ • test services │                        │   │
│  │                     └──────────────────┘                        │   │
│  │                                                                  │   │
│  │                              ▼                                   │   │
│  │  ┌─────────────────────────────────────────────────────┐        │   │
│  │  │              Deployment Decision                    │        │   │
│  │  │  • On merge to main → deploy to all hosts          │        │   │
│  │  │  • Manual trigger → deploy to specific host        │        │   │
│  │  └─────────────────────────────────────────────────────┘        │   │
│  │                              │                                   │   │
│  │                              ▼                                   │   │
│  │                     ┌──────────────────┐                        │   │
│  │                     │   Colmena        │                        │   │
│  │                     │   Deployment     │                        │   │
│  │                     │   (ssh to nodes) │                        │   │
│  │                     └──────────────────┘                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                            │
│                              ▼                                            │
│                     ┌──────────────┐                                    │
│                     │   Cluster    │                                    │
│                     │   (zephyr,    │                                    │
│                     │   nexus,      │                                    │
│                     │   forge,      │                                    │
│                     │   sentry)     │                                    │
│                     └──────────────┘                                    │
└─────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | Push/PR | Main CI pipeline |
| `deploy.yml` | Merge/manual | Deployment to cluster |
| `flake-update.yml` | Weekly | Update dependencies |
| `security-scan.yml` | Schedule/PR | Security scanning |

### 2. Self-Hosted Runner

**Location:** zephyr (primary workstation)
**User:** `actions-runner`
**Labels:** `nixos`, `self-hosted`
**Purpose:** Native NixOS builds with full store cache

### 3. Pre-Commit Hooks

**Tools:** pre-commit framework
**Checks:**
- `nix flake check` - Validate flake
- `statix check` - Nix linting
- `deadnix -f` - Find dead code
- `trailing-whitespace-fixer` - Clean up whitespace
- `end-of-file-fixer` - Ensure newlines at EOF

### 4. Enhanced Justfile

**New targets:**
- `just ci-local` - Run full CI locally
- `just pre-commit-all` - Run pre-commit on all files
- `just flake-update` - Update flake.lock
- `just security-scan` - Run security scan locally
- `just ci-status` - Show CI/CD status

## Data Flow

### CI Pipeline (on PR/Push)

```
1. Trigger (push/PR)
   ↓
2. Quick Check (ubuntu-latest)
   - nix flake check
   ↓
3. Lint (ubuntu-latest)
   - statix check
   - deadnix -f
   ↓
4. Security Scan (ubuntu-latest)
   - osv-scanner
   ↓
5. Build (self-hosted, zephyr)
   - colmena build
   - service health checks
   ↓
6. Status on PR
```

### Deployment Pipeline (on merge to main)

```
1. Merge to main
   ↓
2. Deploy workflow triggered
   ↓
3. Pause mining (xmrig, lolminer)
   ↓
4. Colmena deploy
   - just deploy (all hosts)
   ↓
5. Resume mining
   ↓
6. Health check
   - curl AI gateway on each host
   ↓
7. Notify on failure
```

## Error Handling

### CI Failures

| Failure Type | Action | Recovery |
|--------------|--------|----------|
| Flake check | Block PR | Fix Nix syntax |
| Lint warnings | Warn, don't block | Fix or ignore |
| Security scan | Warn, don't block | Update dependency |
| Build failure | Block PR | Fix config |
| Service down | Warn, don't block | Manual intervention |

### Deployment Failures

| Failure Type | Action | Recovery |
|--------------|--------|----------|
| Build failure | Stop deploy | Fix config, retry |
| Deploy failure | Rollback | `just rollback <host>` |
| Service down | Alert | Manual fix |
| Mining not resume | Alert | Manual start |

## Success Criteria

✅ PRs are validated before merge
✅ Broken configs cannot be deployed
✅ Security vulnerabilities are flagged
✅ Flake lock updated automatically
✅ Pre-commit hooks catch issues locally
✅ Deployments are automated on merge
✅ Rollback is one command away
✅ CI can be run locally (`just ci-local`)

## Implementation Files

### GitHub Actions
- `.github/workflows/ci.yml`
- `.github/workflows/deploy.yml`
- `.github/workflows/flake-update.yml`
- `.github/workflows/security-scan.yml`

### Scripts
- `scripts/ci/setup-runner.sh` - Install self-hosted runner
- `scripts/ci/setup-git-hooks.sh` - Install pre-commit hooks
- `scripts/ci/local-ci.sh` - Run CI locally
- `scripts/ci/health-check.sh` - Check cluster health
- `scripts/deploy/rollback.sh` - Rollback to previous generation

### NixOS Module
- `modules/services/ci-runner.nix` - Self-hosted runner service

### Configuration
- `.pre-commit-config.yaml` - Pre-commit hook definitions
- `justfile` - Enhanced with CI targets

## Security Considerations

| Concern | Mitigation |
|---------|-----------|
| Runner token in logs | Use GitHub secrets, sanitize logs |
| Runner compromised | Isolate runner user, limited permissions |
| Deployment access | Require approval for production |
| Secrets exposure | Use Agenix, never commit secrets |
| Supply chain | osv-scanner for dependencies |

## Monitoring

### Metrics to Track

- CI/CD run time
- Build success rate
- Deployment frequency
- Rollback frequency
- Security scan results

### Alerts

- CI failure on main branch
- Deployment failure
- Service down after deploy
- Mining not resumed

## Future Enhancements

1. **Cachix integration** - Share build cache across runners
2. **Discord/Slack notifications** - Deploy status updates
3. **Multi-runner support** - Runners on each cluster node
4. **Automatic rollback** - On health check failure
5. **Performance testing** - Benchmark before/after deploy
6. **A/B testing** - Deploy to subset of hosts first

## References

- [GitHub Actions](https://docs.github.com/en/actions)
- [Colmena](https://colmena.cli.rs/)
- [pre-commit](https://pre-commit.com/)
- [statix](https://github.com/nerdypepper/statix)
- [deadnix](https://github.com/figsoda/deadnix)
- [osv-scanner](https://github.com/google/osv-scanner)
