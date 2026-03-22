# Kubernetes Documentation Organization

**Last Updated:** 2026-03-22

## Directory Structure

```
docs/kubernetes/
├── README.md                    # This file
├── active/                      # Active implementation plans & docs
├── archived/                    # Completed work & historical summaries
├── incidents/                   # Incident reports & post-mortems
├── runbooks/                    # Operational runbooks & procedures
└── *.md                         # Current reference documentation
```

## Quick Reference

### Active Implementation Plans
- **STATUS: 🟡 ACTIVE** - Files marked with this status are in progress
- Large implementation plans (>1000 lines) should have clear status markers

### Archived Content
- Completed migration phases
- Daily/weekly summaries from 2026-03-21/22 audit period
- Historical status reports

### Incidents
- `akash-provider-incident-2026-03-22.md`
- `ip-exhaustion-incident-2-2026-03-21.md`
- `volcano-scheduler-incident-2026-03-22.md`

### Runbooks
- `disaster-recovery-runbook.md`

## File Naming Conventions

- **Active work:** `feature-name.md` or `plan-name.md`
- **Completed work:** Moved to `archived/`
- **Incidents:** `incident-name-YYYY-MM-DD.md` in `incidents/`
- **Runbooks:** `procedure-name-runbook.md` in `runbooks/`

## Maintenance

When completing implementation plans:
1. Move plan to `archived/`
2. Create summary in main directory if needed
3. Update STATUS marker to `✅ COMPLETE`

**Total Files:** 35 main docs + 10 archived + 3 incidents + 1 runbook = 49 total
