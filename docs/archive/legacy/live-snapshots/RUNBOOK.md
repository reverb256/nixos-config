---
last-verified: 2026-05-24
verified-by: Sisyphus
verification-method: just docs-audit
expires: 2026-05-31
---
# Runbook

> **⚠️ STALE. Last verified 2026-05-24 (>2 months ago at 2026-07-27 audit).**
>
> Per AGENTS.md Pocock Rule, this file must be re-verified before following its claims. Many sections reference files and workflows that may have drifted. In particular: NFS purge completed cluster-wide 2026-07 (`just deploy-*` recipes no longer reference NFS); Z.AI MCP servers removed 2026-07-15; sops-nix → secretspec migration completed 2026-07-25. Re-verify each section before relying on it, or update this header to today's date with the current `verification-method` output.

## Common Operations

**Cluster Status**
```bash
just status
just health
just docs-audit
```

**Deploy Changes**
```bash
just switch          # Local (Zephyr)
just deploy nexus    # Specific host
just deploy all      # Full cluster
```

**Documentation**
```bash
just docs-audit      # Verify all LIVE docs
just docs-freshen    # Refresh stale sections
```

**Critical Rules**
- Never schedule non-infra workloads on Zephyr (OOM risk)
- Update `docs/LIVE/INFRASTRUCTURE-AUDIT.md` on any infrastructure change
- All PRs touching modules/ or hosts/ must pass `just docs-audit`
- If cluster reality diverges from docs, update the docs (Pocock Rule)

## Emergency Procedures

**NFS Issues**
- Check `just check-nfs`
- Restart NFS services on Zephyr if remotes cannot read config

**K8s Issues**
- `kubectl get nodes`
- Check Alloy, Prometheus, Loki on Sentry

See `docs/ARCHIVE/` for historical context only. All current procedures live in this file or INFRASTRUCTURE-AUDIT.md.
