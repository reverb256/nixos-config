## Summary

<!-- One or two sentences describing the change. -->

## Related Issues

<!-- REQUIRED: Link to GitHub issue(s) this PR addresses -->
Closes #   <!-- or: Related to # -->

**No issue = no PR.** Create the issue first if it doesn't exist.

## Worktree Info
- **Developed on:** [zephyr / nexus / forge / sentry]
- **Worktree path:** `/data/projects/own/nixos-config-NNN`
- **Branch:** `issue-NNN-short-description`

## Type of Change

- [ ] Bug fix (non-breaking)
- [ ] Feature / enhancement
- [ ] Infrastructure / NixOS module
- [ ] K8s manifest / deployment
- [ ] Documentation
- [ ] Refactor / cleanup
- [ ] Security hardening

## Hosts Verified

- [ ] Zephyr
- [ ] Nexus
- [ ] Forge
- [ ] Sentry
- [ ] Not host-specific (doc/CI/etc.)

## Testing

- [ ] `just check` passes
- [ ] `nix flake check` passes (or known pre-existing failure noted)
- [ ] Changed hosts build successfully
- [ ] `just deploy` applied on verified hosts
- [ ] No SSH breakage on any node

## Deployment Notes

<!-- Any special steps needed for rollout? -->
- [ ] Requires `just deploy` to take effect
- [ ] Requires SSH access (auth/security changes)
- [ ] Rolling update safe
- [ ] Direct apply via `kubectl` needed (K8s-only change)

## Checklist

- [ ] `lib.mkOptionDefault` used for extensible lists (ports, packages)
- [ ] No `:latest` tags (SHA-pinned or versioned)
- [ ] GPU workloads default to Nexus (not Zephyr)
- [ ] Commit messages reference issue number: `(#NNN)`
- [ ] Branch name: `issue-NNN-short-description`
- [ ] Worktree cleaned up after merge: `git worktree remove /data/projects/own/nixos-config-NNN`
- [ ] Remote nodes synced: each host runs `nix flake update && just switch`
