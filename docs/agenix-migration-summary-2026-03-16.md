# Agenix Migration Summary - 2026-03-16

## Overview

Migrated all host configurations from individual `age.secrets` declarations to the centralized `agenix-secrets-registry` module.

## Changes Made

### 1. Created Central Registry Module
**File**: `modules/system/agenix-secrets-registry.nix`

New module providing category-based secret selection:
- `aiServices` - AI API keys (HuggingFace, LM Studio, ZAI, etc.)
- `monitoring` - Grafana, Sentry
- `storage` - Garage S3, RPC
- `mining` - XMRig API tokens
- `cloud` - Tailscale, Cloudflare, Akash
- `selfHosting` - Nextcloud, Vaultwarden, GlitchTip

### 2. Host Configuration Migrations

#### Zephyr (Control Plane)
**Before**: 180+ lines of individual age.secrets declarations
**After**: Registry with all categories enabled + specific overrides

```nix
services.agenix-secrets-registry = {
  enable = true;
  aiServices = true;
  monitoring = true;
  storage = true;
  mining = true;
  cloud = true;
  selfHosting = true;
};
# Override section for specific permissions (mining, akash, cloudflare)
```

#### Nexus (Storage + Mining)
**Before**: Individual age.secrets for xmrig-always and xmrig-flexible
**After**: Registry with mining and storage categories

```nix
services.agenix-secrets-registry = {
  enable = true;
  mining = true;  # XMRig API tokens
  storage = true; # Garage S3 cluster
};
# Override section for mining service permissions
```

#### Sentry (Monitoring + Mining)
**Before**: Individual age.secrets for xmrig-api-token
**After**: Registry with mining category

```nix
services.agenix-secrets-registry = {
  enable = true;
  mining = true;
};
# Override section for mining service permissions
```

#### Forge (Compute + Mining)
**Before**: No age.secrets configuration
**After**: Added documentation comment for future use

```nix
# No Agenix secrets currently configured for Forge.
# Enable via services.agenix-secrets-registry when needed.
```

### 3. Module Cleanups

#### SearXNG Module
**File**: `modules/services/searxng.nix`

**Issue**: Referenced non-existent `searxng-secret` from agenix
**Fix**: Removed age.secrets reference; module uses environmentFile instead

### 4. Documentation Updates

**Updated Files**:
- `docs/agenix-multi-host-deployment.md` - Added current host configurations
- `DOCUMENTATION_INDEX.md` - Added Agenix Secrets Management section
- This summary document

## Secrets Not Migrated

The following services have their own self-contained age.secrets declarations and were NOT migrated (they're not enabled yet):

- `modules/services/kubernetes-ha.nix` - Kubernetes PKI secrets (when K8s HA is enabled)
- `modules/services/etcd-cluster.nix` - etcd cluster secrets (referenced but not used)

These will work correctly when the services are enabled - they declare their own secrets.

## Pre-existing Issues

**Prometheus Node Exporter**: Unrelated error in `modules/services/hermes-agent/monitor.nix`
- Issue: Uses non-existent option `services.prometheus.exporters.node.extraOpts`
- Status: Pre-existing, not caused by this migration

## Verification Steps

1. **Validate flake**:
   ```bash
   nix flake check
   ```
   Note: May fail due to pre-existing hermes-agent issue

2. **Build local host**:
   ```bash
   just build
   ```

3. **Deploy to all hosts**:
   ```bash
   just deploy
   ```

4. **Verify secrets on hosts**:
   ```bash
   ssh zephyr "ls -la /run/agenix/"
   ssh nexus "ls -la /run/agenix/"
   ssh sentry "ls -la /run/agenix/"
   ```

## Future Enhancements

1. **Kubernetes secrets**: When K8s HA is enabled, add kubernetes category to registry
2. **Forge secrets**: Add cloud category when Akash provider is configured
3. **Validation**: Add automated checking for missing secret references

## Files Modified

```
hosts/zephyr/configuration.nix  | -171 lines (simplified)
hosts/nexus/configuration.nix   |  ±36 lines (migrated)
hosts/sentry/configuration.nix  |  ±24 lines (migrated)
hosts/forge/configuration.nix   |  +7 lines (doc comments)
modules/services/searxng.nix    |  ±7 lines (cleanup)
modules/system/agenix-secrets-registry.nix | (new file)
docs/agenix-multi-host-deployment.md | (updated)
docs/agenix-migration-summary-2026-03-16.md | (new file)
```

## Git Commands

```bash
# Add new files
git add modules/system/agenix-secrets-registry.nix
git add docs/agenix-migration-summary-2026-03-16.md

# Commit
git commit -m "refactor(agenix): migrate to centralized secrets registry

- Create agenix-secrets-registry module for category-based selection
- Migrate all host configs to use registry format
- Clean up SearXNG module (remove unused age.secrets reference)
- Update documentation with current configuration

See: docs/agenix-migration-summary-2026-03-16.md"
```

---

**Migration Date**: 2026-03-16
**Agent**: Claude Code (Serena)
**Status**: Complete (pending deployment)
