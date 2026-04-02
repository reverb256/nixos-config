---
name: nixos-service-worker
description: Fixes service hardening issues (dedicated users, configurable options, threading) and code quality (magic numbers, hardcoded endpoints, linting).
---

# NixOS Service Hardening Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Features involving systemd service hardening, code quality fixes in Python scripts, configurable NixOS module options, and linting/formatting of all modified files.

## Required Skills

None. All work is file editing and shell commands.

## Context

Multiple NixOS services run as root or as the interactive user `j_kro` instead of dedicated system users. Some services have hardcoded IPs, magic numbers, and brittle patterns. This worker fixes service hardening and code quality issues.

**Critical safety rules:**
- Use `lib.mkOptionDefault` for ALL list/attr options in shared modules
- NEVER use `nixos-rebuild switch` or deploy during mission — validate via `nix flake check` only
- NEVER edit `hardware-configuration.nix` or `flake.lock`
- All new system users must have `isSystemUser = true` and `group = "username"`

## Work Procedure

### Step 1: Read all files before editing

Read these files completely:
- `/etc/nixos/modules/system/mining-inference-coordinator.nix`
- `/etc/nixos/modules/services/mining-exporter.nix`
- `/etc/nixos/scripts/manage-models.py`
- `/etc/nixos/modules/services/ai-inference/default.nix` (for magic number context)

### Step 2: Fix mining-inference-coordinator

Convert hardcoded values to NixOS module options:
```nix
options.services.mining-inference-coordinator = {
  enable = mkEnableOption "Mining-Inference Coordinator";
  host = mkOption { type = types.str; default = "127.0.0.1"; description = "Llama.cpp metrics host"; };
  port = mkOption { type = types.port; default = 8083; description = "Llama.cpp metrics port"; };
  miningDeployment = mkOption { type = types.str; default = "gpu-miner-zephyr"; description = "K8s mining deployment to manage"; };
  miningNamespace = mkOption { type = types.str; default = "mining"; };
  checkInterval = mkOption { type = types.int; default = 5; };
  idleTimeout = mkOption { type = types.int; default = 60; };
};
```

Create dedicated system user. Change `User = "j_kro"` to `User = "mining-coord"`. Add kubeconfig path handling.

### Step 3: Fix mining-exporter threaded metrics

Replace the `RuntimeMaxSec` brute-force pattern with a threaded approach:
- Remove `RuntimeMaxSec = 60`
- Restructure the Python HTTP server to use `threading.Thread` for background metric refresh
- The main thread runs the HTTP server, a daemon thread periodically fetches metrics
- Add proper error handling for missing token file (log warning, skip xmrig metrics)

### Step 4: Fix manage-models.py

Replace hardcoded endpoints:
```python
LM_STUDIO = os.environ.get("LM_STUDIO_URL", "http://127.0.0.1:1234")
GATEWAY = os.environ.get("GATEWAY_URL", "http://127.0.0.1:8080")
```

Replace magic number `262144`:
```python
DEFAULT_CONTEXT_LENGTH = 262144  # 256K context (Qwen 3.5)
```

### Step 5: Fix magic number in default.nix

In `/etc/nixos/modules/services/ai-inference/default.nix`, add a named let binding:
```nix
let
  # Named constants for context lengths
  qwen35ContextLength = 262144; # 256K context window
  ...
```
Then replace `262144` with `qwen35ContextLength` in routing rules defaults.

### Step 6: Fix compute-workload-monitor typo

Find `nvidia-safe` (with hyphen) in `compute-workload-monitor.nix` and replace with `nvidia_safe` (underscore). This is a shell function name — hyphens are invalid.

### Step 7: Run full lint suite

After all edits, run on ALL modified files:
1. `cd /etc/nixos && deadnix <all modified .nix files>` — fix any findings
2. `cd /etc/nixos && statix check <all modified .nix files>` — fix any findings
3. `cd /etc/nixos && nix flake check` — must pass
4. `bash -n scripts/manage-models.py` won't work for Python; use `python3 -m py_compile scripts/manage-models.py`

## Example Handoff

```json
{
  "salientSummary": "Converted mining-inference-coordinator to use configurable NixOS options with dedicated system user. Replaced mining-exporter's RuntimeMaxSec with threaded background metric refresh. Made manage-models.py endpoints configurable via env vars. Fixed magic number 262144 with named constant. Fixed nvidia-safe typo. All linting passes.",
  "whatWasImplemented": "Configurable options for mining-inference-coordinator, threaded mining-exporter, configurable script endpoints, named constants, lint fixes",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      { "command": "cd /etc/nixos && nix flake check", "exitCode": 0, "observation": "All 4 host configs build successfully" },
      { "command": "deadnix <all-modified-files>", "exitCode": 0, "observation": "Zero findings" },
      { "command": "statix check <all-modified-files>", "exitCode": 0, "observation": "Zero findings" },
      { "command": "python3 -m py_compile scripts/manage-models.py", "exitCode": 0, "observation": "Syntax valid" }
    ],
    "interactiveChecks": []
  },
  "tests": { "added": [] },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- `nix flake check` fails and the error is in files you didn't modify
- Need to create new agenix secrets (requires interactive user action)
- Changes would require modifying Kubernetes manifests not in scope
