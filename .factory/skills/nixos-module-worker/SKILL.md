---
name: nixos-module-worker
description: Worker for NixOS module refactoring, shell script packaging, and flake validation
---

# NixOS Module Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Use this worker for features that involve:
- Creating or refactoring NixOS modules (`.nix` files)
- Packaging shell scripts via `writeShellScriptBin`
- Updating module imports in `default.nix`
- Updating host configuration references
- Deleting obsolete module files
- Validating via `nix flake check`

## Required Skills

None. All work is NixOS module authoring and shell scripting.

## Work Procedure

1. **Read mission context**: Read `mission.md`, `AGENTS.md`, and any architecture docs referenced in the feature description.

2. **Read existing code**: Before making ANY changes, read the files you'll be modifying or replacing. Understand:
   - The module option structure (options + config)
   - The shell script logic (if any)
   - The imports and how modules connect
   - Host configs that enable the services

3. **Implement the feature**:
   - For new modules: Create the `.nix` file with proper NixOS module structure (`{ config, lib, pkgs, ... }:` with `options` and `config` sections)
   - For shell scripts in modules: Use `pkgs.writeShellScriptBin` and ensure `set -euo pipefail`
   - For list options in shared modules: ALWAYS use `lib.mkOptionDefault` (NEVER direct assignment)
   - Follow 2-space indentation, trailing semicolons, kebab-case filenames

4. **Git track new files**: `git add` any new files before running `nix flake check` (Nix only sees git-tracked files)

5. **Validate with `nix flake check`**: Run `cd /etc/nixos && nix flake check` to verify option types, imports, and all 4 host configs build. If it fails:
   - Read the error carefully
   - Fix the issue
   - Re-run until clean

6. **Commit**: Stage your changes and commit with a descriptive message following repo convention.

7. **Handoff**: Return structured handoff with exact commands run and their results.

## Critical Safety Rules (NEVER VIOLATE)

- **`mkOptionDefault`** for all list/attr options in shared/imported modules
- **Never edit** `hardware-configuration.nix` or `flake.nix`
- **Never run** `nixos-rebuild switch` or `just deploy` -- validation only
- **Always `git add`** new files before `nix flake check`
- **Never use** `sudo` for any operation

## Example Handoff

```json
{
  "salientSummary": "Created modules/gpu-workload/shared.nix with shell library (gpu-workload-lib) containing 25 gw_* functions. All functions extract from compute-workload-monitor without duplication. nix flake check passes for all 4 hosts.",
  "whatWasImplemented": "Created /etc/nixos/modules/gpu-workload/shared.nix (480 lines) containing a writeShellScriptBin 'gpu-workload-lib' package with gaming detection, GPU helpers, profile functions, state management, PSI parsing, and K8s GPU detection. Package added to environment.systemPackages. nix flake check passes.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      {
        "command": "cd /etc/nixos && git add modules/gpu-workload/shared.nix && nix flake check",
        "exitCode": 0,
        "observation": "All 4 hosts validate successfully. No option type errors."
      },
      {
        "command": "grep -c '^gw_' /etc/nixos/modules/gpu-workload/shared.nix",
        "exitCode": 0,
        "observation": "25 gw_* functions defined in shared library"
      },
      {
        "command": "grep -c 'mkOptionDefault' /etc/nixos/modules/gpu-workload/shared.nix",
        "exitCode": 0,
        "observation": "No list options in shared.nix (correct - it only provides a package, no NixOS options that merge)"
      }
    ],
    "interactiveChecks": [],
    "tests": {
      "added": []
    },
    "discoveredIssues": []
  }
}
```

## When to Return to Orchestrator

- `nix flake check` fails and the error is in a module you don't own (not your feature)
- Feature description references a module or option that doesn't exist yet
- Circular dependency detected between modules you're creating
- `hardware-configuration.nix` or `flake.nix` changes would be needed
