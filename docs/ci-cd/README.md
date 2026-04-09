# CI/CD Pipeline

**Status**: ✅ Active | **Updated**: 2026-03-19

---

## Overview

The cluster uses GitHub Actions for CI/CD with justfile commands for local development and Colmena for multi-host deployment.

### Pipeline Architecture

```
GitHub Actions (CI)
    ↓
just check (flake validation)
    ↓
just test (build all hosts)
    ↓
just deploy (colmena apply)
```

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

Always run before pushing:
```bash
just test
```

This builds all 4 host configurations to ensure they compile.

---

## Deployment Workflow

### 1. Make Changes

Edit configuration files on zephyr (source of truth).

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
| `flake-check.yml` | Push, PR | Validate flake syntax |
| `build-test.yml` | Push to main | Build all hosts |
| `colmena-deploy.yml` | Manual | Deploy via Colmena |

### Required Secrets

- `SSH_PRIVATE_KEY`: SSH key for Colmena deployment
- `KNOWN_HOSTS`: SSH known hosts fingerprint

---

## Colmena Multi-Host Deployment

### Configuration

`colmena.nix` defines deployment for all hosts:

```nix
{
  meta = {
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
    };
  };

  zephyr = { ... }: {
    # Workstation configuration
  };

  nexus = { ... }: {
    # Gaming node configuration
  };

  forge = { ... }: {
    # Mining node configuration
  };

  sentry = { ... }: {
    # Monitoring node configuration
  };
}
```

### Deploy via Colmena

```bash
# Deploy to all hosts
colmena apply --refresh

# Deploy to specific host
colmena apply zephyr --refresh

# Build without deploying
colmena build

# Evaluate configuration
colmena eval
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

- [Colmena Documentation](https://github.com/zhaofengli/colmena)
- [NixOS Flakes](https://nixos.wiki/wiki/Flakes)
- [Nix Pills](https://nixos.org/guides/nix-pills/)

---

## History

- **2026-03-19**: Consolidated from 4 separate documents
- **2026-03-11**: CI/CD refactoring completed
- **2026-03-07**: GitHub Actions workflows added
- **2026-03-02`: Initial Colmena deployment
