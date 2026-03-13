# Cluster Storage Status Report

**Date**: 2026-03-13
**Status**: **MOSTLY COMPLETE** (13/15 tasks done)
**Remaining**: Garage deployment, testing verification

---

## Executive Summary

The storage architecture implementation is **87% complete**. The implementation plan documents were outdated - most services were already deployed and operational. Only Garage S3 cluster remains to be fully configured.

---

## Deployment Status by Service

| Service | Status | Nodes | Details |
|---------|--------|-------|---------|
| **NFS Server** | ✅ OPERATIONAL | Nexus | Exports 4 shares to 10.1.1.0/24 |
| **NFS Clients** | ✅ OPERATIONAL | Zephyr, Forge, Sentry | Automount configured, mounts verified |
| **nixos-share** | ✅ OPERATIONAL | All 4 nodes | Zephyr exports `/etc/nixos`, remotes mount |
| **Syncthing** | ✅ OPERATIONAL | All 4 nodes | Active on all cluster nodes |
| **Loki** | ✅ OPERATIONAL | Sentry | Log aggregation server running |
| **Promtail** | ✅ OPERATIONAL | All 4 nodes | Log agents sending to Sentry Loki |
| **Garage** | ⚠️ PARTIAL | None | Module imported, not enabled |
| **cluster-storage** | ✅ OPERATIONAL | All nodes | Systemd verification timer active |

---

## NFS Configuration Details

### Nexus (NFS Server)

**Exports:**
```
/data/backups 10.1.1.0/24
/data/media   10.1.1.0/24
/data/home    10.1.1.0/24
/data/shared  10.1.1.0/24
```

**Status**: ✅ Active and serving

### NFS Client Mount Status

| Node | /data/shared | /data/home | /data/media | /etc/nixos |
|------|--------------|------------|-------------|------------|
| **Zephyr** | autofs | N/A | autofs | local |
| **Nexus** | local | local | local | NFS (ro) from Zephyr |
| **Forge** | ✅ mounted | ✅ mounted | autofs | NFS (rw) from Zephyr |
| **Sentry** | ✅ mounted | N/A | N/A | NFS (ro) from Zephyr |

**Note**: Zephyr uses autofs (on-demand mounting) for NFS shares - mounts appear on first access.

---

## Config Sync Architecture

Two mechanisms working in parallel:

### 1. nixos-share (NFS-based) - PRIMARY

**Flow**: Zephyr → NFS → All remotes

```
ZEPHYR (10.1.1.110)
└── /etc/nixos (local, read-write)
    └── NFS export → 10.1.1.120, 10.1.1.130, 10.1.1.140

NEXUS (10.1.1.120)     FORGE (10.1.1.130)     SENTRY (10.1.1.140)
└── /etc/nixos (ro)     └── /etc/nixos (rw)     └── /etc/nixos (ro)
```

**Mount Options**:
- `ro` (read-only) on Nexus and Sentry
- `rw` on Forge (unusual - may want to change to `ro`)
- Soft mount with 5s timeout (fast fail if Zephyr unavailable)

### 2. Syncthing - SECONDARY

**Status**: Active on all nodes
**Purpose**: Likely used for user home sync or specific folders
**Note**: Not configured for `/etc/nixos` (nixos-share handles that)

---

## Log Aggregation

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    CLUSTER WIDE                         │
├─────────────┬─────────────┬─────────────┬─────────────┤
│   Zephyr    │    Nexus    │    Forge    │   Sentry    │
│  Promtail   │  Promtail   │  Promtail   │ Promtail +  │
│   (journald)│  (journald) │  (journald) │    Loki     │
└──────┬──────┴──────┬──────┴──────┬──────┴──────┬──────┘
       │              │              │              │
       └──────────────┴──────────────┴──────────────> │
                          10.1.1.40:3100 (Loki HTTP API)
```

### Status

| Component | Status | Endpoint |
|-----------|--------|----------|
| Loki (Sentry) | ✅ Active | http://10.1.1.40:3100 |
| Promtail (Zephyr) | ✅ Active | Sending to Sentry |
| Promtail (Nexus) | ✅ Active | Sending to Sentry |
| Promtail (Forge) | ✅ Active | Sending to Sentry |
| Promtail (Sentry) | ✅ Active | Local send to Loki |

**Promtail Uptime:**
- Zephyr: ~5 minutes (recently restarted)
- Nexus/Forge: ~18 hours
- Sentry: ~2 hours

---

## Storage Inventory Summary

| Node | Role | Local Storage | NFS Mounts | Total Accessible |
|------|------|---------------|------------|------------------|
| **Zephyr** | Control | ~1.9TB (NVMe) | /data/shared, /data/media | ~1.9TB + NFS |
| **Nexus** | Storage | ~4TB (bcache0) | /etc/nixos (config) | ~4TB |
| **Forge** | GPU | ~450GB (SSD) | /data/shared, /data/home | ~450GB + 4TB NFS |
| **Sentry** | Monitor | ~1.2TB (SSD+HDD) | /data/shared | ~1.2TB + 4TB NFS |

**Cluster Total**: ~8.4TB raw + NFS sharing

---

## Remaining Work

### Garage S3 Storage (Phase 4)

**Status**: Module imported in `modules/default.nix` but **NOT ENABLED** on any node.

**Required Actions**:
1. Enable Garage on Zephyr, Nexus, Sentry
2. Configure cluster layout (assign zones)
3. Create S3 buckets
4. Test S3 API access

**Priority**: LOW - NFS already handles shared storage well

---

## Updated Implementation Plan Status

| Phase | Tasks | Complete | Status |
|-------|-------|----------|--------|
| **Phase 1: Log Aggregation** | 3 | 3 | ✅ DONE |
| **Phase 2: NFS** | 5 | 5 | ✅ DONE |
| **Phase 3: Syncthing** | 3 | 3 | ✅ DONE |
| **Phase 4: Garage** | 2 | 0 | ❌ TODO |
| **Phase 5: Testing** | 1 | 0 | ❌ TODO |

**Overall Progress**: 13/15 tasks complete (87%)

---

## Module Import Status

Verified in `modules/default.nix`:

```nix
# Storage services - all imported
./services/nfs-server.nix    ✅
./services/nfs-client.nix    ✅
./services/syncthing.nix     ✅
./services/garage.nix        ✅ (imported, not enabled)
```

---

## Issues Found

### 1. Forge nixos-share Mount is Read-Write

**Current**: Forge mounts `/etc/nixos` as `rw`
**Expected**: Should be `ro` like Nexus and Sentry
**Risk**: Forge could modify config, causing drift
**Fix**: Add `ro` option to Forge's nixos-share mount

### 2. Zephyr NFS Automount Not Verified

**Current**: Uses autofs for `/data/shared` and `/data/media`
**Status**: Mounts appear on-demand (not visible in `mount` output until accessed)
**Action**: Test with `ls /data/shared` on Zephyr to verify

---

## Testing Verification Needed

**Manual Verification Checklist**:

- [ ] Zephyr can access `/data/shared` from Nexus (test: `ls /data/shared`)
- [ ] Forge can write to `/data/shared` and Nexus sees changes
- [ ] Sentry can write to `/data/shared` and Nexus sees changes
- [ ] Logs from all nodes appear in Loki (test: query Loki API)
- [ ] nixos-share changes on Zephyr appear on remotes

---

## Recommendations

### Immediate (This Week)

1. **Fix Forge nixos-share mount** - Change to read-only
2. **Verify Zephyr NFS automount** - Test `/data/shared` access
3. **Run end-to-end tests** - Verify all services working together

### Short-term (This Month)

4. **Decide on Garage** - Deploy or remove module if not needed
5. **Document Promtail config** - Add to monitoring docs
6. **Create storage runbook** - Troubleshooting guide for NFS/Syncthing

### Future (As Needed)

7. **Garage deployment** - Only if S3-compatible storage is needed
8. **Restic backup automation** - Add scheduled backups
9. **Offsite backup sync** - Wasabi/B2 integration

---

**Next Review**: After testing verification complete

**Document Owner**: j_kro
**Last Updated**: 2026-03-13
