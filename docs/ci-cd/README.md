# CI/CD Pipeline

> **Status:** Active reference
> **Last Verified:** 2026-08-12
> **Owner:** Cluster operations

---

## Overview

The cluster uses GitHub Actions for CI/CD with justfile commands for local development and Colmena for multi-host deployment.

The declarative self-hosted runner is part of the NixOS configuration. The details below describe the runner configuration in the checked-out source; they become live only after that configuration is deployed. CI validation does not deploy a change. Merge to `main` and the guarded deployment workflow remain separate operations.

### Pipeline Architecture

```
GitHub Actions (CI)
    ↓
just check (flake validation)
    ↓
just build / targeted test validation
    ↓
just deploy (repository safety gates + host-specific build flow)
```

The primary `ci.yml` workflow has five validation stages:

1. **Parse and quick checks:** `Parse Check` parses every Nix file. `Quick Check`
   evaluates the explicit `.#checks.x86_64-linux` output with the evaluation cache
   disabled.
2. **Static analysis:** `Lint Nix` runs Alejandra, Statix, and Deadnix on changed
   Nix files. `Home Path Guard (#309)` runs on Ubuntu and rejects hardcoded
   `/home/j_kro` paths in shared cross-host layers.
3. **Source tests:** `Test Suite` parses every test and strictly asserts its
   `passed = true` or `all_pass = true` result. It depends on `Parse Check`.
4. **Security:** `Security Scan` runs `osv-scanner` and writes `results.sarif`.
   Scanner startup failures fail the job. Vulnerability findings still produce a
   report. SARIF upload is temporarily non-blocking until the deployed runner
   has the declarative Node 20 compatibility wrapper.
5. **Heavy build validation:** `Build Configs` depends on quick checks, lint, and
   source tests. It runs documentation verification, builds `zephyr`, `nexus`,
   `forge`, and `sentry`, then validates the generated Kubernetes manifests.
   The job has a 180-minute timeout. A timeout or cancellation is not a passing
   host-build result. `Security Scan` runs independently in the workflow; whether
   it is required for merge is controlled by repository branch protection, not by
   the `Build Configs` dependency list.

The current verification snapshot for PR #455 is recorded in
[`status-2026-08-12.md`](status-2026-08-12.md). It is time-bound evidence, not a
replacement for live GitHub checks.

---

## Quick Start

### Local Development

```bash
# Validate flake (fast, no build)
just check

# Build for local host
just build

# Apply to local host
just switch

# Deploy to all hosts
just deploy

# Check cluster status
just status
```

### Pre-commit Validation

Always run before committing:
```bash
just check
```

This validates:
- Flake syntax
- Option definitions
- No non-existent options

### Pre-push Validation

Run the fast check and the relevant build validation before pushing:
```bash
just check
just build
```

For a temporary activation test without switching permanently, use:
```bash
just test-apply
```

There is no `just test` recipe. Zephyr builds are offloaded through the
configured remote-build path because Zephyr has zero local build jobs.

---

## Deployment Workflow

### 1. Make Changes

Edit configuration in a dedicated worktree. Zephyr is the authoring/source-of-truth host;
`/etc/nixos` on the deployed hosts is not an independent configuration source.

### 2. Validate

```bash
nix flake check
```

### 3. Commit

```bash
git add <files>
git commit -m "description"
```

**CRITICAL**: Nix only packages git-tracked files! Always `git add` new files.

### 4. Build Locally

```bash
just build
```

### 5. Deploy

```bash
just deploy [<host>]
```

Deploy to all hosts or specific host:
- `just deploy` - All hosts
- `just deploy zephyr` - Control plane only
- `just deploy forge` - Mining node only

---

## GitHub Actions

### Workflow Files

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | Push, PR, manual | Parse, lint, source tests, security scan, and host builds |
| `cache.yml` | Push, PR, manual | Build host closures and populate the Nexus cache (best-effort) |
| `ci-test-automation.yml` | Push, PR, manual | Test coverage and non-blocking auxiliary validation |
| `secretspec-build.yml` | Secretspec-related push/PR, manual | Secretspec schema, ephemeral end-to-end check, and best-effort build |
| `deploy.yml` | Manual / deployment events | Guarded cluster deployment workflow |
| `flake-update.yml` | Weekly schedule, manual | Selective flake-input updates and PR creation |
| `doc-rot-guard.yml` | Daily schedule, docs/config PRs, manual | Documentation freshness and link validation |
| `pr-validation.yml` | Pull requests | Branch, issue-link, commit, and documentation checks |
| `cluster-status.yml` | Every 5 minutes, manual | Report deployment state for all hosts |
| `ci-doctor.yml` | Manual / diagnostic events | CI health diagnostics |
| `recover-host.yml` | Manual | Host recovery procedure |
| `auto-merge-to-prod.yml` | Push to main | Wait for checks and merge main to prod |
| `auto-delete-head-branches.yml` | Pull requests | Remove merged head branches |
| `dependabot-auto-merge.yml` | Dependabot events | Automate approved dependency merges |
| `stale.yml` | Schedule | Stale issue/PR management |
| `update-stability-matrix.yml` | Weekly schedule, manual | Update Stability Matrix package metadata |
| `weekly-git-health.yml` | Weekly schedule | Repository health checks |

### Required Secrets

- `SSH_PRIVATE_KEY`: SSH key for Colmena deployment
- `KNOWN_HOSTS`: SSH known hosts fingerprint
- `CACHIX_AUTH_TOKEN`: token used by cache-enabled workflows
- `GITHUB_TOKEN`: supplied by GitHub for repository API/PR operations

### Self-hosted runner requirements

The self-hosted runner is the declarative `github-actions-runner.service` on
Nexus, running as the `runner` system user from `/var/lib/runner` with the
`self-hosted` and `nixos` labels. The NixOS module provisions `nix`, `cachix`,
`gh`, the GitHub runner, and the shell/tooling used by `run:` steps.

The module wraps the packaged runner and provides `lib/externals/node20` as a
symlink to the bundled Node 24 runtime. This restores actions that still request
Node 20 without maintaining a second runner bundle. The service also sets an
explicit NixOS-safe `PATH`, keeps the runner registration setup persistent, and
removes the stale registration drop-in during activation before reloading
systemd. The runner remains sandboxed with `ProtectSystem = "strict"` while
allowing read-only access to the Nix store, current system profile, and runtime
secrets.

Cachix-enabled workflows pass `cachixBin: /run/current-system/sw/bin/cachix`
because `cachix-action`'s default `nix-env` installer is not reliable under
this system runner service. Keep `cachix` in the system closure and keep the
runner profile on PATH as a fallback.

The repository Actions policy is intentionally allowlisted. The selected-action
allowlist must permit GitHub-owned actions and these third-party namespaces:
`cachix/*` and `peter-evans/*`. Inspect it with:

```bash
gh api repos/reverb256/nixos-config/actions/permissions/selected-actions
```

When adding a third-party action, pin it to a full 40-character commit SHA,
add its owner/repository pattern to the allowlist, and verify both before
merging. A missing allowlist entry can fail a workflow at startup with zero
jobs; a runner/tool failure occurs later and must be diagnosed from job logs.
The allowlist check is intentionally an operator preflight (`scripts/ci/check-actions-policy.sh`),
not a normal workflow step: GitHub's default `GITHUB_TOKEN` does not generally
have repository-administration permission to read Actions policy settings.

---

## Colmena Multi-Host Deployment

### Configuration

The unified `hosts` attribute set in `flake.nix` is the source of truth.
`colmena.nix` receives that set and derives the Colmena nodes, deployment
metadata, target hosts, tags, and shared modules. The checked-in root
`machines` file is passed to Colmena as `meta.machinesFile`; it is distinct
from the generated `/etc/nix/machines` used by the Nix daemon for distributed
builds.

### Deploy via Colmena

```bash
# Recommended: use the repository guardrails
just deploy
just deploy zephyr

# Direct app invocation (only when the just recipe is unsuitable)
nix --option pure-eval false run .#apps.x86_64-linux.colmena -- apply --on zephyr

# Build without deploying
nix --option pure-eval false run .#apps.x86_64-linux.colmena -- build
```

---

## Testing Checklist

### Before Deploying to Production

| Change Type | Test On | Notes |
|-------------|---------|-------|
| `modules/networking/*` | zephyr AND nexus | SSH on both nodes |
| `modules/system/ssh.nix` | ALL 4 nodes | Can't afford SSH breakage |
| `modules/system/users.nix` | ALL 4 nodes | Login test on all nodes |
| `modules/default.nix` | Entire cluster | High-impact change |

### Stop Immediately If

- SSH breaks on any node → Document incident, wait for human
- Multiple nodes affected → STOP ALL WORK
- `nix flake check` fails → Fix errors before proceeding

---

## Troubleshooting

### Build Failures

```bash
# Show detailed error
nix build .#nixosConfigurations.zephyr.config.system.build.toplevel

# Check for undefined options
nix flake show

# Search for option usage
grep -r "undefinedOption" modules/
```

### Deployment Failures

```bash
# Check host connectivity
ping zephyr
ssh zephyr echo "connected"

# Verify Colmena config
colmena eval

# Deploy with verbose output
colmena apply --verbose --refresh
```

### Rollback

```bash
# Rollback local host
sudo nixos-rebuild rollback

# Rollback remote host
ssh zephyr sudo nixos-rebuild rollback
```

---

## Best Practices

1. **Always validate** before committing (`just check`)
2. **Test locally** before deploying (`just build`)
3. **Deploy incrementally** for high-risk changes
4. **Monitor logs** during deployment (`journalctl -f`)
5. **Rollback immediately** if something breaks
6. **Document incidents** in `docs/incidents/`

---

## References

- [Current CI verification snapshot](status-2026-08-12.md)
- [Colmena Documentation](https://github.com/zhaofengli/colmena)
- [NixOS Flakes](https://nixos.wiki/wiki/Flakes)
- [Nix Pills](https://nixos.org/guides/nix-pills/)

---

## History

- **2026-03-19**: Consolidated from 4 separate documents
- **2026-03-11**: CI/CD refactoring completed
- **2026-03-07**: GitHub Actions workflows added
- **2026-03-02**: Initial Colmena deployment
