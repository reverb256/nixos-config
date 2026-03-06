---
name: nix-rebuild
description: NixOS rebuild deploy apply switch test flake check build workflow. Use for: rebuild, deploy, apply changes, test config, nixos-rebuild, update system.
disable-model-invocation: false
---

# NixOS Rebuild Workflow

## Trigger Keywords
rebuild, deploy, apply, switch, test, nixos-rebuild, flake, build, update, nixos

## Step 1: Ask User
**Question**: Which host? (Options: zephyr, forge, nexus, sentry)
**Default**: zephyr (if user doesn't specify)

## Step 2: Run Workflow (IN ORDER)

### Step 2.1: Check Syntax (5 seconds)
```bash
nix flake check
```
**Expected output**: "checking flake output..." (no errors)

### Step 2.2: Build Only (1-2 minutes)
```bash
sudo nixos-rebuild build --flake .#HOSTNAME
```
**Expected output**: "building the system configuration..." followed by "Done."

### Step 2.3: Test (optional - rolls back on reboot)
```bash
sudo nixos-rebuild test --flake .#HOSTNAME
```
**Expected output**: "activating the configuration..."

### Step 2.4: Switch (permanent - ask user first)
```bash
sudo nixos-rebuild switch --flake .#HOSTNAME
```
**Expected output**: "setting up /etc..."

## Few-Shot Examples

### Example 1: User says "rebuild"
```
User: rebuild
Model: [ASK] Which host? (default: zephyr)
User: zephyr
Model: [RUN] nix flake check
      [RUN] sudo nixos-rebuild build --flake .#zephyr
      [RUN] sudo nixos-rebuild switch --flake .#zephyr
```

### Example 2: User says "test my changes on forge"
```
User: test my changes on forge
Model: [SKIP asking - host specified]
      [RUN] nix flake check
      [RUN] sudo nixos-rebuild test --flake .#forge
```

### Example 3: User says "apply to all hosts"
```
User: apply to all hosts
Model: [RUN] just deploy
      (This uses colmena to deploy to all hosts)
```

## Host Reference

| Host | Type | Command |
|------|------|---------|
| zephyr | Local | `sudo nixos-rebuild switch --flake .#zephyr` |
| forge | Remote | `just forge` |
| nexus | Remote | `just nexus` |
| sentry | Remote | `just sentry` |
| all | Remote | `just deploy` |

## Error Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| "attribute missing" | Module not imported | Add to `modules/default.nix` |
| "undefined variable" | Nix string escape | Use `''${variable}` not `${variable}` |
| "permission denied" | Need sudo | Use `sudo nixos-rebuild` |
| "flaky" | Build randomly fails | Run again (Nix caching issue) |
| "service failed" | Service error | Check `journalctl -u SERVICE` |

## Important Rules

1. **ALWAYS run `nix flake check` first** - catches syntax errors fast
2. **Ask before `switch`** - test mode is safer for experiments
3. **Remote hosts use `just` commands** - not nixos-rebuild directly
4. **zephyr is local** - use sudo nixos-rebuild directly
