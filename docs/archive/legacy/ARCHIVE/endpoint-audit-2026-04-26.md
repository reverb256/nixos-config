# Endpoint Audit & Parameterization — Session Summary

**Date:** 2026-04-26 | **Status:** Complete (zephyr, forge, sentry build clean; nexus pre-existing issue)

---

## 1. What Triggered This

User asked "check all network endpoints" — discovered widespread hardcoded IPs, dead DNS zones, and fragile K8s ClusterIP references across the entire codebase.

## 2. Audit Findings

### DNS Layer
| Issue | Severity | Fix |
|-------|----------|-----|
| CoreDNS `.lan` forward tried nexus first (`sequential`) | P0 | Changed to `round_robin`, zephyr first |
| CoreDNS NodeHosts: `10.1.1.100` (VIP) mapped to `search.lan` | P0 | Removed wrong entry |
| `privacy-filter.lan` had no DNS record | P0 | Added A record pointing to nexus |
| `cluster.local` was dead static zone in unbound | P0 | Replaced with `forward-zone` to CoreDNS |
| CoreDNS `clusterDNS = "10.0.0.10"` was correct | OK | Verified |

### K8s Service Layer
| Issue | Severity | Fix |
|-------|----------|-----|
| `ingress-nginx` LoadBalancer stuck `<pending>` (no cloud provider) | P1 | Documented as redundant with Caddy |
| `infra/redis-ai-gateway` and `infra/vaultwarden` have no endpoints | P1 | Dead services (pods not running) |
| `kb-mcp` pod in `ErrImageNeverPull` state | P2 | Pre-existing, not addressed |
| `debug-patch` pod in `StartError` on forge | P2 | Pre-existing, not addressed |

### NixOS Module Layer
| Issue | Severity | Fix |
|-------|----------|-----|
| 12 ClusterIP backends in nexus Caddy (ephemeral, break on recreation) | P1 | Replaced with K8s service DNS |
| `network-constants.nix` only defined 1 of 16 services | P1 | Expanded with full service registry |
| 40+ hardcoded IPs across 13 files | P2 | Parameterized to `config.networking.cluster.*` |
| `or "fallback"` anti-pattern in 5 files | P2 | Replaced with direct option references |

## 3. Files Modified

### Foundation
- `modules/network-constants.nix` — 16-service registry, nodePorts, clusterDnsIP
- `modules/network/cluster-dns.nix` — privacy-filter.lan, cluster.local forward zone

### Host Configs
- `hosts/zephyr/services.nix` — 6 IPs parameterized
- `hosts/forge/services.nix` — 2 IPs parameterized
- `hosts/sentry/services.nix` — 5 IPs parameterized
- `hosts/nexus/services.nix` — k3s IPs + 12 ClusterIP backends → K8s DNS

### Service Modules
- `modules/services/vane.nix` — SearXNG URL → K8s DNS
- `modules/services/health-checks.nix` — 2 fallback patterns removed
- `modules/services/hermes-cli.nix` — 2 fallback patterns removed
- `modules/development/ai-coding-tools.nix` — fallback pattern removed

### K8s Modules (easykubenix — no `config` access)
- `kubernetes/modules/vane.nix` — gateway URL → K8s DNS constant
- `kubernetes/modules/monitoring.nix` — `hostIPs` constant for scrape targets

### Live K8s Changes (kubectl apply)
- `coredns` ConfigMap — removed wrong NodeHosts entry
- `coredns-custom` ConfigMap — round_robin forward, zephyr first
- CoreDNS deployment restarted to pick up new config

## 4. Architecture Improvement: DNS Resolution Chain

**Before:**
```
Host service → 127.0.0.1:53 (unbound)
  → cluster.local → NXDOMAIN (dead static zone)
  → nexus Caddy → 10.15.67.242 (hardcoded ClusterIP)
```

**After:**
```
Host service → 127.0.0.1:53 (unbound)
  → cluster.local → 10.0.0.10:53 (CoreDNS)
  → nexus Caddy → searxng.search.svc.cluster.local (stable DNS)
```

## 5. Build Validation

| Host | Status | Notes |
|------|--------|-------|
| zephyr | Builds clean | Primary workstation |
| forge | Builds clean | GPU mining node |
| sentry | Builds clean | Monitoring + ROCm |
| nexus | Pre-existing issue | `nfs-data-server` option (in-progress user work) |

## 6. Bugs Found & Fixed During Implementation

| Bug | Cause | Fix |
|-----|-------|-----|
| `attribute 'kubernetes' missing` | Submodule `readOnly = true` with no `default` | Removed `readOnly`, added `default = {}` |
| File corruption (line-number prefixes) | Linter modified configuration.nix | Restored from git |

## 7. What's Left (Not Addressed)

- Nexus `nfs-data-server` option (user's in-progress work)
- `infra/redis-ai-gateway` and `infra/vaultwarden` dead services
- `kb-mcp` ErrImageNeverPull pod
- `ingress-nginx` LoadBalancer pending (redundant with Caddy)
- `debug-patch` StartError pod on forge
- Full deploy to all hosts (waiting for nexus to come back up)
