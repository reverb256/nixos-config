# Issue #8: patches/ audit — retire or re-derive 4 broken patches

**Priority:** MED  
**Status:** Open  
**Created:** 2026-07-25  
**Origin:** `git apply --check` against all 4 patches in `/etc/nixos/patches/` returned errors. Three are clearly broken by upstream drift; one is corrupt mid-patch.  
**Depends on:** none  
**Blocks:** none, but a hazard.

## Context

```
$ for p in /etc/nixos/patches/*.patch; do echo "--- $p ---"; git apply --check "$p" 2>&1 | head -3; done
- hermes-cua-backend-linux.patch: error: No valid patches in input (allow with --allow-empty)
- niri-sdr-brightness.patch: error: niri-config/src/output.rs: No such file or directory
- noctalia-sdr-brightness.patch: error: src/config/config_types.h: No such file or directory
- openrazer-hid-report-6args.patch: error: corrupt patch at /etc/nixos/patches/openrazer-hid-report-6args.patch:47
```

Each patch was authored against a specific upstream-SHA-C snapshot. Upstream has drifted:
- niri-config moved output.rs somewhere else (or removed).
- noctalia's src/config/config_types.h location or structure changed.
- openrazer-hid was authored long ago; the upstream kernel Hid driver has changed.

## Acceptance Criteria

- Decision recorded per patch (retire, re-derive, or mark as future-work-item).
- Either regenerated patches applicable-grep-cleanly via `git apply --check`, OR explicit commit deleting retired patches with rationale comment.

## Approach

1. For each patch, lookup the upstream SHA it was authored against (commit messages likely contain the SHA or the date).
2. Decide: 
   - If upstream feature is now in mainline -> retire patch (delete + commit comment).
   - If upstream feature has moved -> re-derive (some manual work; budget operator time).
   - If patch is dep-only required -> mark future-work.
3. Apply: rm or re-write per decision.
4. Commit with rationale in commit message.

## Decision-Skeleton (operator to fill)

- `hermes-cua-backend-linux.patch`: empty patch (no content). RETIRE.
- `niri-sdr-brightness.patch`: upstream drift. RE-DERIVE (budget 1-2 hours) or RETIRE if upstream merged.
- `noctalia-sdr-brightness.patch`: similar drift. RE-DERIVE or RETIRE.
- `openrazer-hid-report-6args.patch`: corrupt at line 47. RE-DERIVE from upstream openrazer-driver git history.

## Related

- `patches/` directory
- `sodiboo/niri` flake input
- `noctalia` flake input
