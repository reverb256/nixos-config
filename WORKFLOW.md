---
# WORKFLOW.md — NixOS Cluster Agent Contract
#
# This file follows the Symphony SPEC.md convention (v1 draft):
# YAML front matter for config, markdown body for the prompt template.
# Changes are hot-reloaded by the pipeline engine without restart.
# Version-controlled with the infrastructure — PR reviews apply to agent behavior too.

tracker:
  kind: github
  active_labels: [enhancement, bug, agent-ready, p1, p2]
  exclude_labels: [blocked, wontfix, duplicate, discussion]
  terminal_states: [closed, merged]

polling:
  interval_ms: 30000

workspace:
  root: /tmp/nixos-worktrees
  kind: worktree

hooks:
  after_create: |
    git clone --depth 1 --bare file:///etc/nixos/.git /tmp/nixos-bare 2>/dev/null || true
    git --git-dir=/tmp/nixos-bare worktree prune
  before_run: |
    cd {path} && nix flake lock --recreate 2>/dev/null || nix flake lock
  after_run: |
    cd {path} && nix flake check --no-build 2>&1 | tail -5
    echo "exit_code=$?"
  before_remove: |
    rm -rf {path} 2>/dev/null || true
  timeout_ms: 60000

agent:
  max_concurrent_agents: 4
  max_turns: 10
  max_retry_backoff_ms: 300000

proof:
  require_build: true
  require_pr: true
  require_ci: true
---

# NixOS Infrastructure Agent

You are working on the NixOS cluster infrastructure — issue `{{ issue.number }}: {{ issue.title }}`.

{% if attempt %}
**Continuation context** — this is retry attempt #{{ attempt }}. The issue is still open.
Resume from the current workspace state. Do NOT redo already-completed steps.
Focus on what remains open or what changed since the last attempt.
{% endif %}

## Repository Layout

```
/etc/nixos/
├── flake.nix                   # Main flake entry
├── colmena.nix                 # Multi-host deployment definition
├── justfile                    # just check, just switch, just deploy
├── hosts/<hostname>/           # Per-host configs
├── modules/                    # ~171 .nix files
├── kubernetes/                 # K8s via easykubenix (21 modules)
├── scripts/                    # Utilities
├── packages/                   # Custom Nix packages
├── secrets/                    # Agenix-encrypted secrets
└── tests/                      # NixOS tests
```

## CRITICAL SAFETY RULES

1. **mkOptionDefault** for lists (ports, packages, systemd.services)
2. **Zephyr OOM prevention** — default workloads to Nexus (46GB RAM)
3. **No NixOS containers** — use K8s or systemd services
4. **Never edit hardware-configuration.nix**
5. **`nix flake check` MUST pass** before any PR
6. **No `:latest` tags** — pinned container versions only

## REQUIRED WORKFLOW

1. **Understand the issue** — read full body, comments, linked PRs
2. **Check current state** — `gh issue view {{ issue.number }} --json state,labels,assignee`
3. **Create worktree** — `git worktree add /tmp/nixos-worktrees/{{ issue.number }} -b issue-{{ issue.number }}-{{ issue.title | slugify }}`
4. **Implement** — make changes with mkOptionDefault where needed
5. **Gate: nix flake check** — must pass clean:
   ```
   cd {workspace.path} && nix flake check --no-build
   ```
6. **Commit** — `git add -A && git commit -m "type(scope): description (#{{ issue.number }})"`
7. **Push** — `git push origin HEAD`
8. **PR** — `gh pr create --base main --title "type: description (#{{ issue.number }})" --body "Closes #{{ issue.number }}"`
9. **Verify CI** — `gh pr checks --watch`
10. **Complete** — report back with PR URL

## Completion Bar

- [ ] Issue fully understood
- [ ] Changes implemented with mkOptionDefault where applicable
- [ ] `nix flake check --no-build` passes
- [ ] Commit with `(#N)` reference
- [ ] PR created with `Closes #N`
- [ ] CI green
