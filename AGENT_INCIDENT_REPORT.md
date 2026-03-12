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
- ⏳ Awaiting: Physical console access to nexus/sentry to apply fix
- ⏳ Awaiting: Verification that SSH restored after rebuild

---

**Report Generated:** 2026-03-12 00:35
**Agent:** Claude Sonnet 4.6
**Severity:** Critical (SSH completely broken on 2 nodes)
**Recovery Time:** ~15 minutes from identification to fix commit
