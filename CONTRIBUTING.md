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

## CI trust boundary

Pull-request workflows run on ephemeral GitHub-hosted runners with read-only
permissions. They must not access cluster SSH keys, `/run/secrets`, or the
Nexus cache. Cache population, secretspec builds, and host builds that need
persistent infrastructure run only after trusted commits reach `main`.

The required PR checks are:

- `Parse Check`
- `Quick Check`
- `Lint Nix`
- `Test Suite`
- `Security Scan`
- `Build Configs`
- `Home Path Guard (#309)`
- `PR checks`

A required check must fail closed. Do not add `continue-on-error`, `|| true`,
or warning-only handling to these jobs. Advisory jobs must use a separate
name and must not be listed as required checks.

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
