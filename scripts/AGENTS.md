# Scripts - Agent Context

**Parent:** `../AGENTS.md` | **Domain:** Utility scripts (101 files)

## Overview
Utility scripts for cluster operations, GPU management, and deployment workflows.

## Structure
```
scripts/
├── gpu-profiles/        # GPU configuration (9 files)
├── maintenance/         # System maintenance
├── deployment/          # Deploy helpers
├── monitoring/          # Metrics collection
├── backup/              # Backup utilities
└── *.py/*.sh            # Individual scripts (75+)
```

## Where To Look

| Task | Location |
|------|----------|
| GPU fan control | `gpu-profiles/fan-control.sh` |
| Deploy helpers | `deployment/` |
| System health | `maintenance/` |
| Backup scripts | `backup/` |
| Pre-deploy checks | `pre-deploy-check.sh` |
| CI test wrapper | `test-ci-cd-wrapper.sh` |

## Anti-Patterns (THIS DIRECTORY)

| Pattern | Why | Fix |
|---------|-----|-----|
| Hardcoded paths | Not portable | Use `$HOME`, `$XDG_CONFIG_HOME` |
| No error handling | Silent failures | Add `set -euo pipefail` |
| No logging | Hard to debug | Add `log()` function |
| Missing shebang | Wrong interpreter | Always add `#!/usr/bin/env bash` |

## Key Conventions

### Script Template
```bash
#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# Main logic
log "Starting..."
```

### Common Patterns
- Use `log()` for all output
- Check dependencies early: `command -v jq >/dev/null || die "jq required"`
- Use `trap 'cleanup' EXIT` for cleanup
- Exit codes: 0=success, 1=error, 2=usage
