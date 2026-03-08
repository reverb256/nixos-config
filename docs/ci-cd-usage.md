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

Go to Actions -> Deploy -> Run workflow -> Select target host.

### Troubleshooting

#### CI failures

Check GitHub Actions tab for detailed logs.

#### Deployment failures

```bash
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
