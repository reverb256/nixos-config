# Code Deprecation & Disabled Features Tracking

**Last Updated:** 2026-04-02 | **Auto-tracked:** Yes

This file tracks all temporarily disabled modules, TODOs, and FIXMEs in the NixOS configuration code. Use this to prioritize re-enablement.

---

## Critical - Should Fix This Sprint

| ID | File | Line | Description | Status | Target |
|----|------|------|-------------|--------|--------|
| ~~CODE-001~~ | ~~modules/default.nix~~ | ~~16-19~~ | ~~`lib/systemd-helpers.nix`, `lib/firewall-helpers.nix` DISABLED~~ | ✅ **FIXED 2026-04-02** | - |
| ~~CODE-002~~ | ~~modules/default.nix~~ | ~~30~~ | ~~`system/dns-watchdog.nix` DISABLED - rebuild failures~~ | ✅ **REMOVED 2026-04-02** (redundant with CoreDNS) | - |
| CODE-003 | `modules/default.nix` | 31 | `system/interface-naming.nix` DISABLED - Using native naming (2026-03-12) | 🟡 Legacy | 2026-04-05 |
| CODE-004 | `modules/default.nix` | 155 | `lib/option-helpers.nix` DISABLED - "Being fixed (2026-03-23)" | 🔴 Broken | 2026-04-05 |
| CODE-005 | `modules/default.nix` | 163 | `lib/advanced-types.nix` DISABLED - "Being fixed (2026-03-23)" | 🔴 Broken | 2026-04-05 |

---

## High Priority - Should Fix This Month

| ID | File | Line | Description | Status | Target |
|----|------|------|-------------|--------|--------|
| CODE-010 | `modules/default.nix` | 125 | `services/llama-server.nix` TODO - Nix source caching issue | 🟡 Incomplete | 2026-04-15 |
| CODE-011 | `modules/default.nix` | 147 | `services/unbound-cluster.nix` DISABLED - Using unbound-common instead | 🟡 Legacy | 2026-04-15 |
| CODE-012 | `modules/services/crash-watchdog.nix` | 9 | TEMPORARILY DISABLED - Helper libraries being fixed | 🔴 Broken | 2026-04-15 |
| CODE-013 | `hosts/zephyr/configuration.nix` | 634 | NFS mounts DISABLED - "Nexus NFS server is down, causing hangs" | 🟡 Down | 2026-04-15 |
| CODE-014 | `hosts/zephyr/configuration.nix` | 483 | Service broken, blocking rebuild (2026-03-21) | 🔴 Broken | 2026-04-15 |
| CODE-015 | `modules/services/spacebot.nix` | 35 | TODO: pin to specific version (using :latest) | 🟠 Security | 2026-04-15 |

---

## P1: Container Image :latest Tags (Security)

**These violate supply chain policy. Fix immediately.**

| ID | File | Line | Image | Status | Target |
|----|------|------|-------|--------|--------|
| K8S-001 | `kubernetes-manifests/mining/*.yaml` | 39,62 | `lolminer:latest` | 🟠 Security | 2026-04-05 |
| K8S-002 | `kubernetes-manifests/mining/*.yaml` | 46 | `xmrig-nixos:latest` | 🟠 Security | 2026-04-05 |
| K8S-003 | `kubernetes-manifests/n8n/*.yaml` | 130 | `n8nio/n8n:latest` | 🟠 Security | 2026-04-05 |
| K8S-004 | `kubernetes-manifests/glitchtip/*.yaml` | 22 | `glitchtip/glitchtip:latest` | 🟠 Security | 2026-04-05 |
| K8S-005 | `kubernetes-manifests/spacebot/*.yaml` | 45,56 | `spacebot:latest` | 🟠 Security | 2026-04-05 |
| K8S-006 | `kubernetes-manifests/searxng/*.yaml` | 22,93 | `searxng/searxng:latest` | 🟠 Security | 2026-04-05 |

---

## Medium Priority - Review This Quarter

| ID | File | Line | Description | Status | Target |
|----|------|------|-------------|--------|--------|
| CODE-020 | `hosts/zephyr/configuration.nix` | 271 | TEMPORARILY DISABLED - IPv6 routing issues | 🟡 KnownIssue | 2026-05-01 |
| CODE-021 | `hosts/zephyr/configuration.nix` | 1114 | TODO: monitoring re-enable after sentry-dsn.age | 🟡 Blocked | 2026-05-01 |
| CODE-022 | `hosts/zephyr/configuration.nix` | 1190 | TODO: mining-plasmoid requires plasmoids/mining-monitor | 🟡 Incomplete | 2026-05-01 |
| CODE-023 | `modules/gaming/gaming.nix` | 345 | TEMPORARILY DISABLED - Build failing (2026-03-27) | 🟡 KnownIssue | 2026-05-01 |
| CODE-024 | `modules/gaming/gaming.nix` | 414 | TEMPORARILY DISABLED - Build failing (2026-03-27) | 🟡 KnownIssue | 2026-05-01 |
| CODE-025 | `hosts/sentry/configuration.nix` | 505 | `llama-cpp-rocm` DISABLED - Build failing | 🟡 KnownIssue | 2026-05-01 |

---

## Low Priority / Legacy

| ID | File | Line | Description | Status | Target |
|----|------|------|-------------|--------|--------|
| CODE-030 | `hosts/sentry/configuration.nix` | 266 | CPU mining DISABLED - K8s deployment scaled to 0 | 🔵 Legacy | TBD |
| CODE-031 | `hosts/sentry/configuration.nix` | 281 | AMD GPU DISABLED for AI inference | 🔵 Legacy | TBD |
| CODE-032 | `hosts/nexus/configuration.nix` | 43 | Nix binary cache DISABLED | 🔵 Legacy | TBD |
| CODE-033 | `hosts/nexus/configuration.nix` | 410-450 | GPU/CPU mining DISABLED - K8s version working | 🔵 Legacy | TBD |
| CODE-034 | `hosts/forge/configuration.nix` | 714-718 | Fan speed service DISABLED - Using fan curve | 🔵 Legacy | TBD |

---

## Quick Commands

```bash
# Find all disabled items
rg -n 'DISABLED|TEMPORARILY DISABLED' --glob '*.nix'

# Find all :latest tags (security issue)
rg -n ':latest' --glob '*.yaml'

# Find all TODOs
rg -n 'TODO:' --glob '*.nix'
```

---

## Status Meanings

| Status | Meaning | Action |
|--------|---------|--------|
| 🔴 Broken | Causes build failures | Fix immediately |
| 🟠 Security | Security risk (:latest, secrets) | Fix this sprint |
| 🟡 KnownIssue | Known problem, documented | Fix this month |
| 🟡 Incomplete | Feature not finished | Complete this month |
| 🟡 Blocked | Waiting on another task | Unblock or document |
| 🔵 Legacy | Intentionally disabled | Review for removal |
| ✅ Fixed | Issue resolved | Keep for reference |
