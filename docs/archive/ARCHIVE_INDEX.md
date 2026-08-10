# Documentation Archive Index

> **Status:** Canonical archive catalog
> **Last Verified:** 2026-08-09
> **Owner:** Documentation maintenance

This directory contains historical, superseded, and deprecated documentation. Archived
content is preserved for auditability and context; it is not an operational authority.
Re-verify every command against the current repository before use.

## Structure

```text
docs/archive/
├── ARCHIVE_INDEX.md                 # This catalog
├── obsolete/                        # Superseded or explicitly incorrect references
└── legacy/
    ├── ARCHIVE/                     # Former uppercase archive, preserved intact
    └── live-snapshots/              # Former docs/LIVE snapshots, preserved intact
```

The `legacy/ARCHIVE/` tree includes a nested external project documentation tree. It is
intentionally not flattened because duplicate filenames and historical relative links
must remain unambiguous.

## Current archive policy

- Preserve incident reports, audits, completed plans, and research with their original
  dates and outcomes.
- Mark superseded operational guidance as historical and never refresh its verification
  date merely to make a check pass.
- Put new completed plans and obsolete references under `docs/archive/` using a clear
  topic directory.
- Add a pointer at an old path only when compatibility or discoverability requires it.
- Update this index whenever files are moved or a new archive category is introduced.

## Retired LIVE documentation

The former `docs/LIVE/` files are preserved under:

- `legacy/live-snapshots/INDEX.md`
- `legacy/live-snapshots/ARCHITECTURE.md`
- `legacy/live-snapshots/INFRASTRUCTURE-AUDIT.md`
- `legacy/live-snapshots/STATUS.md`
- `legacy/live-snapshots/RUNBOOK.md`

Use `docs/current-state.md`, root `STATUS.md`, and active runbooks instead.

## Former uppercase archive

The former `docs/ARCHIVE/` tree is preserved at `legacy/ARCHIVE/`. Its original index is
retained as historical material at `legacy/ARCHIVE/INDEX.md`; this catalog is the current
entry point for the archive as a whole.

## Finding current information

1. Start at `DOCUMENTATION_INDEX.md`.
2. Read `docs/current-state.md` for checked-in architecture and authority boundaries.
3. Use `just status`, `just health`, and `just provenance` for runtime/deployment evidence.
4. Treat any archived document as historical unless it has been independently verified.
