# Contributing to NixOS Cluster Config

## Workflow
Every change follows: **Issue → Branch/Worktree → PR → Merge → Close Issue**

## Node Targeting
| Change Type | Primary Node | Verify On |
|-------------|-------------|-----------|
| Shared module | Zephyr | ALL 4 nodes |
| Host-specific | Affected host | That host |
| K8s deployment | Nexus | Nexus |
| Security/auth | Zephyr | All affected |

## SSH Workaround
`ssh nexus 'bash --norc --noprofile -c "command"'`

## Code Standards
### Nix
- 2-space indent, mkOptionDefault for lists, getExe for ExecStart
### Commits
`type(scope): description (#NNN)`

## PR Checklist
- [ ] Single issue per PR
- [ ] Worktree on affected host
- [ ] `just check` passes
- [ ] Affected hosts build
- [ ] Branch: issue-NNN-desc
- [ ] Commit messages reference (#NNN)
- [ ] PR body: Closes #NNN
- [ ] No :latest tags
- [ ] GPU workloads pinned to Nexus
- [ ] Worktree cleaned up after merge
