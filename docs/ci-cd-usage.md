# CI/CD Usage Guide

## Architecture

The CI/CD system uses a **nixos-rebuild wrapper** that translates commands to Colmena for cluster-wide deployment consistency.

**Wrapper Features:**
- Translates `nixos-rebuild` commands to Colmena automatically
- Pauses CPU mining (xmrig) during builds, GPU mining (lolminer) continues
- Writes deployment state to `/run/nixos-deploy/{host}.json`
- All deployment paths use Colmena (justfile, GitHub Actions, manual)

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

Merge to `main` or `master` triggers deployment to all hosts via GitHub Actions.

#### Manual (via justfile)

```bash
just deploy            # Deploy to all 4 hosts
just zephyr            # Deploy to Zephyr only
just nexus             # Deploy to Nexus only
just forge             # Deploy to Forge only
just sentry            # Deploy to Sentry only
```

#### Manual (direct wrapper)

```bash
# Wrapper translates to Colmena automatically
sudo nixos-rebuild switch --flake .#zephyr   # Local deployment
sudo nixos-rebuild build --flake .#nexus     # Remote build
```

### Mining Behavior

**CPU Mining (xmrig):**
- Automatically paused during builds
- Automatically resumed after builds (success or failure)
- Wrapper detects active services before pausing

**GPU Mining (lolminer):**
- Continues running during builds
- No automatic pause/resume
- Maximizes GPU mining revenue

### Troubleshooting

#### CI failures

Check GitHub Actions tab for detailed logs.

#### Deployment failures

```bash
# Check deployment state
cat /run/nixos-deploy/$(hostname).json

# Check logs
journalctl -u github-actions-runner -f

# Rollback
just rollback <host> <generation>
```

#### Runner not starting

```bash
# Check service
sudo systemctl status github-actions-runner

# Restart
sudo systemctl restart github-actions-runner
```

#### Wrapper bypass (native nixos-rebuild)

```bash
# Use native nixos-rebuild directly
NIXOS_REBUILD_NATIVE=1 sudo nixos-rebuild switch --flake .#zephyr
```

## Distributed Builds

All 4 nodes participate in distributed builds:
- **Zephyr**: 8 maxJobs (control plane, conservative)
- **Nexus**: 6 maxJobs (storage worker, NFS headroom)
- **Forge**: 2 maxJobs (GPU worker, minimal builds)
- **Sentry**: 4 maxJobs (monitoring worker)

Each host automatically excludes itself from the build machines list to avoid SSH-to-self loopback.
