# Phase 0: Security Baseline

**Status:** ✅ COMPLETE - Configuration fixes done, nix-mineral enabled on zephyr
**Created:** 2026-04-22 | **Updated:** 2026-04-23
**Owner:** j_kro

## Executive Summary

Phase 0 establishes the security foundation before implementing CI/CD infrastructure. This phase focuses on system hardening and configuration validation to ensure a stable baseline.

## Completed Tasks

### ✅ 1. Pre-existing Configuration Issues (RESOLVED)

Fixed 14 configuration errors blocking all host builds:

| File | Issue | Fix |
|------|-------|-----|
| backup-to-garage.nix | `config.networking.cluster.hosts.zephyr.ip` not available | Hardcoded `10.1.1.110` |
| node-exporter.nix | `config.networking.cluster.ports.node-exporter` not available | Hardcoded `9100` |
| nixos-share.nix | Multiple `config.networking.cluster.hosts.*` access issues | Hardcoded IPs with fallback |
| cluster-hosts.nix | Circular dependency when accessing `config.networking.cluster.hosts` | Added `or {}` fallback |
| garage.nix | Batch fix broke Nix syntax (`10.1.1.110 or "127.0.0.1"`) | Reverted to proper access pattern |
| unbound-common.nix | Syntax errors (orphaned braces, wrong nesting) | Rewrote with correct structure |
| hermes-cli.nix | `${10.1.1.120}` interpreted as float | Removed unnecessary `${}` |
| rclone.nix | `${10.1.1.110}` in example string | Removed `${}` |
| vane.nix | `${10.1.1.120}` in default value | Removed `${}` |
| cluster-services.nix | Unquoted IP `10.1.1.120` as default | Added quotes |
| nfs-client.nix | Unquoted IP `10.1.1.120` as default | Added quotes |
| network-constants.nix | `listenAddress` option missing default | Added `default = ""` |
| cluster-dns.nix | `listenAddress` access threw error | Used `attrByPath` with null fallback |

**Build Status:** All 4 hosts (zephyr, nexus, forge, sentry) now build successfully.

### ✅ 2. nix-mineral Integration (ZEPHYR)

Enabled nix-mineral on zephyr with **compatibility preset** (safe for gaming/VR/desktop):

```nix
inputs.nix-mineral.nixosModules.nix-mineral

nix-mineral = {
  enable = true;
  preset = [ "performance" "compatibility" ];
};
```

**Conflict Resolved:**
- NixOS default `environment.etc.gitconfig.source` conflicted with nix-mineral
- Fixed with `lib.mkForce` override in zephyr configuration

## nix-mineral Presets

According to [nix-mineral documentation](https://github.com/cynicsketch/nix-mineral):

| Preset | Purpose | Impact |
|--------|---------|--------|
| **default** | Balanced security and usability | Medium hardening |
| **compatibility** | Desktop/gaming/VR (least aggressive) | Minimal hardening, preserves game compatibility |
| **maximum** | Server/isolated systems | Most aggressive hardening |
| **performance** | HPC/AI workloads | Minimal overhead |

**Current Choice:** `["performance" "compatibility"]`
- **Why:** Zephyr is a gaming/VR/desktop workstation + AI workstation
- **Trade-off:** Accepts slightly reduced hardening for GPU/game compatibility
- **Future:** Consider `["compatibility"]` only if performance preset causes issues

## Remaining Tasks

### 1. Deploy nix-mineral to All Hosts

Apply appropriate presets per host role:

| Host | Preset | Rationale |
|------|--------|-----------|
| **zephyr** | `["performance" "compatibility"]` | ✅ DONE - Gaming/VR/desktop + AI |
| **nexus** | `["compatibility"]` | Desktop + AI inference gateway |
| **forge** | `["performance"]` | GPU compute/mining (no desktop) |
| **sentry** | `["compatibility"]` | Desktop + monitoring |

**Implementation:**
```nix
# Add to each host's configuration.nix imports:
inputs.nix-mineral.nixosModules.nix-mineral

# Then configure per-host preset:
nix-mineral = {
  enable = true;
  preset = [ "compatibility" ];  # Adjust per table above
};
```

### 2. Systemd Hardening (Optional)

nix-mineral provides systemd hardening via presets. For additional hardening:

```nix
# Example: Add to modules/system/systemd-hardening.nix
systemd.services."<service-name>" = {
  serviceConfig = {
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    NoNewPrivileges = true;
    # See nix-mineral source for full list
  };
};
```

**Recommendation:** Defer until after nix-mineral is deployed to all hosts and tested.

### 3. Verify Hardening

After deployment, verify:

```bash
# Check systemd service hardening
systemctl show <service-name> | grep -E "(ProtectSystem|ProtectHome|PrivateTmp)"

# Audit running services
systemd-analyze security

# Check for unhardened services
systemd-analyze security --summary --no-pager
```

## Decision Log

### LUKS/Secure Boot (SKIPPED)

**Decision:** Ignore LUKS disk encryption and Secure Boot for now.

**Rationale:**
- User directive: "ignore the LUKS and secure boot thing for now"
- Focus on CI/CD safety and supply chain security
- Can revisit in future security iterations

**Supply Chain Security (IN SCOPE):**
- ✅ Flakes + flake.lock (immutable inputs)
- ✅ Agenix secrets (encrypted at rest)
- ✅ 7-day package manager cooldowns
- ✅ nix-mineral (system hardening)
- ✅ Container image pinning (no `:latest` tags)
- 📋 Planned: Pin critical flake inputs (hermes-agent, nixpkgs)

## Dependencies

### External
- nix-mineral: https://github.com/cynicsketch/nix-mineral
- NixOS modules: services.k3s, networking.cluster

### Internal
- All hosts must build successfully ✅
- nix-mineral input added to flake.nix ✅

## Success Criteria

- ✅ All 4 hosts build without errors
- ✅ nix-mineral enabled on zephyr with compatibility preset
- ⏳ nix-mineral deployed to all hosts
- ⏳ Systemd services audited for hardening gaps
- ⏳ Documentation updated with hardening choices

## Next Steps

1. **Deploy nix-mineral to all hosts** (nexus, forge, sentry)
2. **Test gaming compatibility** on zephyr (Steam, Lutris, Heroic)
3. **Test AI workloads** (llama-server, mining coordination)
4. **Proceed to Phase 1: CI/CD Safety** (see PHASE-1-CICD-SAFETY.md)

## References

- **nix-mineral research:** nix-mineral-research.md
- **Master plan:** MASTER-PLAN.md
- **CI/CD safety:** PHASE-1-CICD-SAFETY.md

---

**Last Updated:** 2026-04-23
**Status:** Configuration fixes complete, nix-mineral enabled on zephyr
