# Legacy Documentation Preservation Record

> **Status:** Historical migration record
> **Created:** 2026-08-09
> **Purpose:** Detect accidental loss of preserved documentation during future cleanup

The former `docs/ARCHIVE/` tree and the former `docs/LIVE/` snapshots were moved under
`docs/archive/legacy/` without flattening or deleting their contents. The baseline at
migration contains **183 files**. The nested external project under
`legacy/ARCHIVE/external/` is intentionally preserved as a separate historical tree.

The verification suite requires the legacy tree to contain at least this baseline count
and checks sentinel indexes/snapshots. Historical relative links may refer to the original
repository layout or appear inside code examples; they are not silently rewritten as part
of the migration. Use the canonical archive index and current-state document for live
navigation.
