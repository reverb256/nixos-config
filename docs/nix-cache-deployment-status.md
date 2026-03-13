# NixOS Binary Cache - Deployment Status

**Last Updated:** 2026-03-13
**Status:** ✅ Operational

## Summary

NixOS binary cache server deployed on Zephyr to provide pre-built binaries for all cluster nodes, reducing build times and memory pressure during deployments.

Inspired by: https://www.nijho.lt/post/nixos-cache/

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Zephyr (Build Server)                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  nix-serve (port 50000)                                    │ │
│  │  Serves /nix/store as binary cache                         │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  nix-auto-build.timer (02:00 UTC)                         │ │
│  │  Nightly builds: zephyr, nexus, sentry, forge             │ │
│  │  Saves .rev files to /var/lib/nix-auto-build              │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
          │                    │                    │
          ▼                    ▼                    ▼
    ┌─────────┐         ┌──────────┐        ┌──────────┐
    │ Nexus   │         │  Forge   │        │ Sentry  │
    │ Client  │         │  Client  │        │  Client  │
    └─────────┘         └──────────┘        └──────────┘
```

## Service Status

| Service | Status | Details |
|---------|--------|---------|
| **nix-serve** | ✅ Running | HTTP on :50000, 6 workers |
| **nix-auto-build.timer** | ✅ Active | Runs 02:00 UTC (21:00 CDT) |
| **Firewall (50000)** | ✅ Open | Accessible from all nodes |

## Client Configuration

All nodes have the binary cache configured as a substituter:

```nix
# modules/common-host-defaults.nix
nix.settings = {
  substituters = lib.mkOptionDefault [
    "http://zephyr.tigris-ule.ts.net:50000?trusted=1"
  ];
};
```

## Deployment Workflow

### Standard (with cache)
```bash
# Nodes use cached binaries when available
just deploy
```

### Forced Rebuild
```bash
# Build locally, bypassing cache
nixos-rebuild switch --flake .#hostname --no-substitute
```

### Manual Cache Query
```bash
curl http://zephyr.tigris-ule.ts.net:50000/nix-cache-info
```

## Module Files

| File | Purpose |
|------|---------|
| `modules/services/nix-cache/harmonia.nix` | nix-serve server |
| `modules/services/nix-cache/auto-build.nix` | Nightly build service |
| `scripts/upgrade-from-cache.sh` | Client deployment script |

## Known Issues

### nvtop Temporarily Disabled
- **Issue:** cuda_compat derivation broken (empty src attr)
- **Workaround:** nvtopPackages.full disabled in hardware/monitoring.nix
- **Impact:** No GPU monitoring in nvtop (use other tools)
- **TODO:** Re-enable after cuda_compat fixed in nixpkgs

### Garage Cluster
- **Issue:** garage-cluster not fully deployed (Colmena bug)
- **Status:** Only Sentry running, Zephyr/Nexus pending
- **TODO:** Investigate service creation failure

## Verification Commands

```bash
# Check cache server status
systemctl status nix-serve

# Check auto-build timer
systemctl list-timers | grep nix-auto

# Test cache accessibility
curl http://10.1.1.110:50000/nix-cache-info

# View available builds
ls -la /var/lib/nix-auto-build/*.rev

# Check recent builds
journalctl -u nix-auto-build -n 50
```

## Next Steps

1. **Monitor first auto-build** (tonight at 02:00 UTC / 21:00 CDT)
2. **Verify .rev files** created in `/var/lib/nix-auto-build`
3. **Test cache hit** by deploying another node after build
4. **Consider adding prometheus metrics** for cache hit rate
5. **Re-enable nvtop** once cuda_compat is fixed

## References

- Original inspiration: https://www.nijho.lt/post/nixos-cache/
- nix-serve documentation: https://github.com/NixOS/nix/tree/master/src/nix-serve
- NixOS substituters: https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-substituters
