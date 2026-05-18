---
name: Task / Chore
about: Track cleanup, migration, or defined work
title: ''
labels: cleanup
assignees: ''
---

## Task
One-line summary.

## Steps
- [ ] Step 1
- [ ] Step 2
- [ ] Verification

## Hosts Affected
- [ ] Zephyr
- [ ] Nexus
- [ ] Forge
- [ ] Sentry
- [ ] All

## Workflow
- [ ] Work in worktree: `git worktree add -b issue-NNN-desc /data/projects/own/nixos-config-NNN main`
- [ ] Single PR per task
- [ ] Branch: `issue-NNN-short-description`
- [ ] Commit messages reference `(#NNN)`
- [ ] PR body contains `Closes #NNN`
- [ ] `just check` passes
- [ ] `just deploy` tested on affected hosts
- [ ] PR reviewed before merge (even solo)

## Context
Why is this necessary? Any constraints or risks?

## Reference
- Plan file: `docs/plans/...`
- Related issue: #
