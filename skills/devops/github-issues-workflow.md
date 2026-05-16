---
name: github-issues-workflow
description: MANDATORY workflow for tracking all non-trivial work in GitHub Issues. Use before starting any task taking >15 minutes.
type: devops
---

# GitHub Issues Workflow

**MANDATORY:** All non-trivial work MUST be tracked in GitHub Issues.

## When to Create an Issue

Create an issue BEFORE starting work if:

- Task takes >15 minutes
- Security hardening (P1 priority)
- Features or polish (P2 priority)
- Bug fixes with cross-file impact
- Module expansion or data integration
- Frontend changes
- Infrastructure changes

## Repository

**ALL issues go to:** `reverb256/maplespike`

```bash
gh issue create --repo reverb256/maplespike <args>
```

NixOS cluster issues ALSO go to MapleSpike (nixos-config has issues disabled).

## Workflow

### 1. Check for Existing Issues

```bash
gh issue list --repo reverb256/maplespike
gh issue list --repo reverb256/maplespike --label p1  # High priority
gh issue list --repo reverb256/maplespike --label p2  # Medium priority
```

### 2. Create Issue

```bash
gh issue create --repo reverb256/maplespike \
  --title "Short descriptive title" \
  --body "## Context

What needs to be done and why.

## Tasks

- [ ] Task 1
- [ ] Task 2

## Est

2h" \
  --label "p1,p2"  # Use p1 for security, p2 for features
```

### 3. Claim Work

```bash
gh issue edit --repo reverb256/maplespike <number> --assignee "@me"
```

### 4. Mark In Progress

```bash
gh issue edit --repo reverb256/maplespike <number> --add-label "in-progress"
```

### 5. Reference in Commits

```bash
# Using Closes #<number> auto-closes when PR merges
git commit -m "feat: implement X

Closes #42"

# Or use Refs #<number> to just reference
git commit -m "fix: Y

Refs #42"
```

### 6. Close When Done

```bash
gh issue close --repo reverb256/maplespike <number>
```

## Labels

| Label | Color | Meaning |
|-------|-------|---------|
| `p1` | orange | High priority — security, stabilization |
| `p2` | blue | Medium priority — features, polish |
| `security` | red | Security-related |
| `k8s` | cyan | Kubernetes work |
| `frontend` | yellow | UI/portal work |
| `module` | teal | Data module work |
| `in-progress` | gray | Work currently active |

## View Issue Details

```bash
gh issue view --repo reverb256/maplespike <number>
gh issue view --repo reverb256/maplespike <number> --comments
```

## Quick Reference

| Action | Command |
|--------|---------|
| List all | `gh issue list --repo reverb256/maplespike` |
| Create | `gh issue create --repo reverb256/maplespike -t "Title" -b "Body"` |
| View | `gh issue view --repo reverb256/maplespike <number>` |
| Claim | `gh issue edit --repo reverb256/maplespike <number> --assignee "@me"` |
| Close | `gh issue close --repo reverb256/maplespike <number>` |

## Before ANY Task

1. Search existing issues: `gh issue list --repo reverb256/maplespike --search "keyword"`
2. If exists, reference it: `Refs #<number>`
3. If not, create it first
4. Claim and mark in-progress
5. Reference in commit message
6. Close when done

## Existing Issues (2026-05-16)

| # | Title | Priority |
|---|-------|----------|
| 1 | P1 Phase 4: Monitoring Egress Restrictions | p1 |
| 2 | P1 Phase 5: AutomountServiceAccountToken Cleanup | p1 |
| 3 | P1 Phase 6: Image Tag Pinning | p1 |
| 4 | P1 Phase 7: PSA Enforcement Labels | p1 |
| 5 | P1 Phase 8: Resource Limits | p1 |
| 6 | P2 Batch 1: Frontend Interactive Wiring | p2 |
| 7 | P2 Batch 2: Content Polish | p2 |
| 8 | P2 Batch 3: Caddy Routing Fix | p2 |
| 9 | P2 Portal Refinement | p2 |
| 10 | P2 Module Expansion: Tests & CRTC | p2 |
| 11 | P2 Tier 1 Gap: Immigration & Borders | p2 |
| 12 | P2 Tier 1 Gap: Indigenous Relations | p2 |
| 13 | P2 Tier 1 Gap: Criminal Justice & Corrections | p2 |
| 14 | P2 Tier 1 Gap: Transport Safety (TSB) | p2 |
| 15 | P2 Tier 1 Gap: Defence & Veterans (DND/VAC) | p2 |