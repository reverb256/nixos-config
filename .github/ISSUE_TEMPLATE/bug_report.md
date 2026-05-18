---
name: Bug report
about: Something isn't working in the cluster
title: ''
labels: bug
assignees: ''
---

## Describe the bug
A clear and concise description of what the bug is.

## To Reproduce
Steps to reproduce the behavior:
1. Go to '...'
2. Run '....'
3. See error

## Expected behavior
What you expected to happen.

## Environment
- **Host affected:** [zephyr / nexus / forge / sentry / all]
- **Service affected:** [e.g., caddy, k3s, llama-server, gateway, maplespike-api]
- **Flake commit:** `git log -1 --oneline`
- **Worktree:** `/data/projects/own/nixos-config-<NNN>` (if applicable)
- **K8s namespace:** [if applicable]

## Logs
```
Paste relevant output
```

## Workflow Check
- [ ] Issue created before any code changes
- [ ] Work in a worktree on the affected host
- [ ] Branch follows `issue-NNN-short-description`
- [ ] PR will be created before merge
- [ ] Tested on all affected hosts before PR

## Additional context
- Regression? (was it working before?)
- `just check` passes?
- Recent changes?
- Related issue: #
