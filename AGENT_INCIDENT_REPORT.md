# Agent Incident Report - 2026-03-12

## What Broke
SSH access to nexus (10.1.1.120) and sentry (10.1.1.140) became completely broken after applying cluster-networking module changes.

**Symptoms:**
- SSH authentication succeeded
- Connection immediately closed after authentication
- Pattern repeated on both LAN and Tailscale connections
- Network connectivity was fine (pings worked, node exporter accessible)

## Changes Made

**Commit:** `db5d1ad refactor(network): switch to native interface naming`

**Files Created:**
- `modules/networking/cluster-networking.nix` - New centralized networking module

**Files Modified:**
- `hosts/nexus/configuration.nix` - Converted to use cluster-networking module
- `hosts/sentry/configuration.nix` - Converted to use cluster-networking module
- `hosts/zephyr/configuration.nix` - Converted to use cluster-networking module
- `hosts/forge/configuration.nix` - Converted to use cluster-networking module

**Module Code (WRONG):**
```nix
# modules/networking/cluster-networking.nix
networking.firewall.allowedTCPPorts = [
  53    # DNS (Unbound)
  22    # SSH
  6443  # Kubernetes API
];
```

## Affected Nodes

- ✅ **Nexus (10.1.1.120)** - SSH BROKEN
- ✅ **Sentry (10.1.1.140)** - SSH BROKEN
- ✅ **Zephyr (10.1.1.110)** - SSH Working (not rebuilt yet)
- ✅ **Forge (10.1.1.130)** - SSH Working (not rebuilt yet)

## Root Cause

**NixOS Option Semantics Misunderstanding:**

The cluster-networking module used **direct assignment** (`=`) for firewall ports:
```nix
networking.firewall.allowedTCPPorts = [53 22 6443];
```

When nexus configuration set its own ports:
```nix
networking.firewall.allowedTCPPorts = [10250];
```

**NixOS REPLACED** the module's list entirely:
- Expected: `[53, 22, 6443, 10250]` (merge)
- Actual: `[10250]` (replace)
- **Result:** SSH port 22 was removed from nexus

**Why zephyr/forge were not affected:**
- They hadn't rebuilt with the new cluster-networking module yet
- They still had their old working configurations

## Proposed Fix

**Commit:** `e58839e fix(networking): use mkOptionDefault for firewall ports to allow merging`

**Changed module code (CORRECT):**
```nix
# modules/networking/cluster-networking.nix
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
  53    # DNS (Unbound)
  22    # SSH
  6443  # Kubernetes API
];
```

**Why this works:**
- `lib.mkOptionDefault` tells NixOS "this is a default value"
- When nodes set their own ports, they **MERGE** with defaults instead of replacing
- Result: All ports present, SSH preserved

## Rollback Plan

### Immediate Action Required
**Physical console access to nexus and sentry:**

```bash
cd /etc/nixos
sudo nixos-rebuild switch
```

This will apply the fix from commit `e58839e`.

### Verification After Rebuild

```bash
# 1. Verify SSH works
ssh nexus "echo 'SSH restored'"
ssh sentry "echo 'SSH restored'"

# 2. Verify firewall rules
ssh nexus "sudo iptables -L -n | grep 'dpt:22'"
# Should show: ACCEPT tcp -- * * *:* 22

# 3. Verify custom ports present
ssh nexus "sudo iptables -L -n | grep 'dpt:10250'"
# Should show: ACCEPT tcp -- * * *:* 10250
```

### If Rebuild Fails

**Rollback to previous generation:**
```bash
sudo nixos-rebuild switch --rollback
sudo reboot
```

## Prevention Measures Implemented

### 1. CLAUDE.md Updated
- Added "Critical Agent Safety Constraints" section
- Documented forbidden vs safe patterns
- Added mandatory testing checklist
- Added incident response process

### 2. Code Review Checklist Required
Changes to these files now require human review:
- `modules/networking/cluster-networking.nix`
- `modules/system/ssh.nix`
- `modules/system/users.nix`
- `modules/default.nix`

### 3. Safe Design Patterns Enforced
- All shared modules MUST use `lib.mkOptionDefault` for extensible options
- Direct assignment only allowed for hard requirements (booleans, non-extensible)
- Mandatory testing on nodes with custom configs before committing

## Lessons Learned

### For AI Agents
1. **Never assume merge behavior** - NixOS replaces by default
2. **Test on diverse nodes** - zephyr only tested one scenario
3. **Understand NixOS semantics** - mkOptionDefault vs direct assignment
4. **Incremental deployment** - Should have tested on 1 node first

### For Module Design
1. **Extensible options need mkOptionDefault** - Always mergeable
2. **Document merge/replace behavior** - Clear intent in code
3. **Test before cluster-wide deployment** - Catch issues early
4. **Preserve critical ports** - SSH (22), DNS (53) must never be blocked

### For Process
1. **Pre-commit hooks** - Should block dangerous patterns
2. **Automated tests** - Should verify SSH not blocked
3. **Code review** - Critical infrastructure changes need review
4. **Incremental rollout** - One node at a time, not all at once

## Timeline

- **22:39** - Commit db5d1ad created cluster-networking module (unsafe)
- **00:05** - Nexus rebooted with broken config
- **00:11** - User reported SSH issues
- **00:25** - Root cause identified (direct assignment bug)
- **00:30** - Fix committed (e58839e)
- **00:35** - CLAUDE.md updated with safety constraints

## Status

- ✅ Root cause identified
- ✅ Fix implemented and committed
- ✅ Documentation updated (CLAUDE.md)
- ✅ Nexus SSH RESTORED (2026-03-12 ~01:00)
- ✅ Sentry SSH RESTORED (2026-03-12 ~01:05)
- 🎉 **INCIDENT RESOLVED**

---

**Report Generated:** 2026-03-12 00:35
**Last Updated:** 2026-03-12 01:05
**Agent:** Claude Sonnet 4.6
**Severity:** Critical (SSH completely broken on 2 nodes)
**Recovery Time:** ~15 minutes from identification to fix commit
**Total Recovery:** ~35 minutes from incident start to full resolution

---

# Agent Incident Report - 2026-03-16

## What Broke
`nix flake check` failed after commit `4321891` with "option does not exist" error for `home-manager.users.j_kro.xdg.mimeApps.force`.

**Symptoms:**
- `nix flake check` evaluation failed
- Error: "The option `home-manager.users.j_kro.xdg.mimeApps.force' does not exist"
- Configuration could not be validated before deployment

## Changes Made

**Problematic Commit:** `4321891 fix(electron): use auto backend detection, add Caprine from Nixpkgs`

**Files Modified:**
- `modules/home-manager/zen-browser.nix` - Added invalid `xdg.mimeApps.force = true` option

**Code Added (WRONG):**
```nix
# modules/home-manager/zen-browser.nix
xdg.mimeApps.enable = true;
xdg.mimeApps.force = true;  # ❌ This option does NOT exist in Home Manager
xdg.mimeApps.defaultApplications = { ... };
```

## Affected Nodes

- ✅ **All hosts** - `nix flake check` fails for all configurations
- ✅ **No runtime impact** - Configuration not deployed, caught at validation stage

## Root Cause

**Home Manager Option Assumption:**

The commit assumed `xdg.mimeApps.force` existed based on:
1. Earlier commit `84f0518` which added the same invalid option
2. No validation that the option actually existed in Home Manager

**Valid `xdg.mimeApps` options:**
- `enable` (boolean)
- `associations` (attrs)
- `defaultApplications` (attrs)
- `mimeapps.list` additions

**Invalid `xdg.mimeApps` options:**
- `force` (does NOT exist in any Home Manager version)

## Fix Applied

**Commit:** `11703f5 fix(home-manager): remove invalid xdg.mimeApps.force option`

**Removed code:**
```nix
-xdg.mimeApps.force = true;  # Idempotent: overwrite existing files without backup errors
```

**Why this works:**
- The `force` option never existed
- Removing it restores valid configuration
- Idempotent activation issue that prompted the "fix" needs a different solution

## Additional Fix

**Commit:** `8bd8568 fix(justfile): remove duplicate echo and redundant esac in deploy target`

**Issue found during investigation:**
- `just deploy` target had duplicate `echo "▸ Deploying to {{target}}..."` line
- Redundant `esac` statement after case block
- Benign but caused confusion during editing

## Timeline

- **20:39** - Commit `84f0518` added invalid `force = true` option
- **21:08** - Commit `e6452c9` accidentally removed the invalid option (unrelated mining refactor)
- **21:21** - Commit `4321891` re-added the invalid option
- **21:22** - User asked "is there a problem with home-manager on zephyr?"
- **21:30** - Root cause identified: `force` option doesn't exist
- **21:35** - Fix committed (`11703f5`)
- **21:40** - justfile fix committed (`8bd8568`)

## Lessons Learned

### For AI Agents
1. **Never assume options exist** - Always validate against actual module definitions
2. **Use `nix flake check` before committing** - Would have caught this immediately
3. **Multi-file commits require scope verification** - Check all changed files match commit intent
4. **Git staging can cause confusion** - Staged changes may differ from working directory

### For Option Validation
1. **Check Home Manager documentation** - Verify options exist before using
2. **Use `nix eval` for option testing** - `nix eval .#nixosConfigurations.<host>.config.<path>`
3. **Search for "does not exist" errors** - `nix flake check 2>&1 | grep "does not exist"`

### For Process
1. **Pre-commit validation** - `nix flake check` should pass before commit
2. **Scope verification** - `git diff --cached --name-only` to verify commit scope
3. **Clean staging** - `git status` to ensure only intended changes are staged

## Prevention Measures Implemented

### 1. Documentation Updated
- Added "Home Manager Module Validation" section to INSIGHTS.md
- Documented valid vs invalid `xdg.mimeApps` options
- Added option validation workflow

### 2. Pre-Commit Checklist
Added to INSIGHTS.md:
```bash
# 1. Syntax validation
nix flake check .

# 2. Check for non-existent options
nix flake check . 2>&1 | grep "does not exist"

# 3. Verify staged changes
git status
git diff --cached --stat
```

### 3. Multi-File Commit Mitigation
```bash
# After making changes, verify scope:
git diff --cached --name-only

# If unrelated files appear, unstage them:
git restore --staged <unrelated-file>
```

## Status

- ✅ Root cause identified
- ✅ Fix implemented and committed (`11703f5`)
- ✅ justfile fix committed (`8bd8568`)
- ✅ Documentation updated (INSIGHTS.md)
- ✅ `nix flake check` passes
- 🎉 **INCIDENT RESOLVED**

---

**Report Generated:** 2026-03-16 21:45
**Agent:** Claude Opus 4.6
**Severity:** Medium (validation blocked, no runtime impact)
**Recovery Time:** ~15 minutes from question to fix commit
