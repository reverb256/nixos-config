---
name: nixos-config-worker
description: Worker for NixOS configuration simplification (shared defaults, deduplication, dead code removal)
---

# NixOS Config Worker

NOTE: Startup and cleanup are handled by `mission-worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Features that involve simplifying NixOS module files: extracting shared defaults, removing duplicate code, deleting dead modules, fixing import lists, and consolidating config patterns across hosts.

## Required Skills

None (all tools are standard bash/file editing)

## Work Procedure

1. **Read the feature description carefully** - understand which files need changing and what the expected behavioral equivalence is
2. **Read ALL target files before editing** - understand the full context of each host's config and the shared modules
3. **Make changes following NixOS conventions**:
   - Use `lib.mkDefault` / `lib.mkOptionDefault` for shared defaults (NEVER direct assignment in shared modules)
   - Use `lib.getExe` for single executables
   - Use `lib.makeBinPath` for PATH construction
   - 2-space indentation, trailing semicolons
   - kebab-case for filenames
   - Preserve all host-specific overrides exactly as-is
4. **After each logical change, validate immediately**:
   - `cd /etc/nixos && nix flake check` — must pass
   - If it fails, fix before proceeding to the next change
5. **Build for all 4 hosts** to verify no regressions:
   - `cd /etc/nixos && nixos-rebuild build` (local/Zephyr)
   - For remote hosts: `colmena apply --build-on-target --on nexus --on forge --on sentry --no-submit` (dry-run)
6. **Verify behavioral equivalence**:
   - Before making changes, capture the evaluated config: `nix eval .#nixosConfigurations.zephyr.config.networking.firewall.allowedTCPPorts` (or relevant option)
   - After changes, verify the same eval produces identical output
   - For each host that was modified, verify the change didn't accidentally alter its config
7. **Commit**: Stage only changed files, commit with descriptive message

### Critical Safety Rules

- **NEVER** use direct assignment for lists/attrs in shared modules — always use `lib.mkDefault` / `lib.mkOptionDefault`
- **NEVER** modify `hardware-configuration.nix` files
- **NEVER** change service behavior — only move where config is defined
- **ALWAYS** verify `nix flake check` passes before committing
- If moving a setting from host config to shared default, verify the host config no longer needs it (no `lib.mkForce` override in host)

### Verifying Behavioral Equivalence

For settings being moved to shared defaults:
```bash
# Before the change, capture the effective value
nix eval /etc/nixos#nixosConfigurations.<host>.config.<option-path> 2>/dev/null || echo "option not set"

# After the change, verify same output
nix eval /etc/nixos#nixosConfigurations.<host>.config.<option-path> 2>/dev/null || echo "option not set"
```

For services being extracted:
```bash
# Check the systemd service definition is identical
nix eval /etc/nixos#nixosConfigurations.<host>.config.systemd.services.<name>.serviceConfig.ExecStart
```

## Example Handoff

```json
{
  "salientSummary": "Moved 5 shared defaults from all 4 host configs to common-host-defaults.nix (systemd.network.links, networking.cluster-hosts, services.unbound-common, security.caddyCa, services.status-auto-update). Removed duplicate corsair.nix and gpu-compute.nix imports from default.nix. Deleted dead common-host.nix. nix flake check passes, nixos-rebuild build succeeds for all 4 hosts.",
  "whatWasImplemented": "Added 5 mkDefault entries to common-host-defaults.nix. Removed corresponding lines from all 4 host configuration.nix files. Deleted duplicate imports (lines 179-180) from modules/default.nix. Removed common-host.nix entirely. Verified behavioral equivalence via nix eval for each moved option on all 4 hosts.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      { "command": "cd /etc/nixos && nix flake check", "exitCode": 0, "observation": "All checks passed" },
      { "command": "cd /etc/nixos && nixos-rebuild build", "exitCode": 0, "observation": "Zephyr config builds successfully" },
      { "command": "cd /etc/nixos && nix eval .#nixosConfigurations.zephyr.config.services.unbound-common.enable", "exitCode": 0, "observation": "true (same as before)" },
      { "command": "cd /etc/nixos && nix eval .#nixosConfigurations.nexus.config.networking.cluster-hosts.enable", "exitCode": 0, "observation": "true (same as before)" },
      { "command": "cd /etc/nixos && nix eval .#nixosConfigurations.forge.config.security.caddyCa.enable", "exitCode": 0, "observation": "true (same as before)" },
      { "command": "cd /etc/nixos && nix eval .#nixosConfigurations.sentry.config.services.status-auto-update.enable", "exitCode": 0, "observation": "true (same as before)" }
    ],
    "interactiveChecks": []
  },
  "tests": { "added": [] },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- `nix flake check` fails and the fix requires changes outside the feature scope
- Feature requires modifying files that belong to another pending feature
- Behavioral equivalence cannot be verified (config evaluates differently after change)
- Host config has unexpected overrides that conflict with the shared default
