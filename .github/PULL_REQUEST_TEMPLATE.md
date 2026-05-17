## Summary

<!-- One or two sentences describing the change. -->

## Related Issues

<!-- REQUIRED: Link to GitHub issue(s) this PR addresses -->
Closes #   <!-- or: Related to # -->

## Type of Change

- [ ] Bug fix (non-breaking)
- [ ] Feature / enhancement
- [ ] Infrastructure / NixOS module
- [ ] K8s manifest / deployment
- [ ] Documentation
- [ ] Refactor / cleanup
- [ ] Security hardening

## Testing

- [ ] `just check` passes
- [ ] `nix flake check` passes (or known pre-existing failure noted)
- [ ] Changed hosts build successfully
- [ ] Verified on: [zephyr / nexus / forge / sentry / all]

## Deployment Notes

<!-- Any special steps needed for rollout? -->
- [ ] Requires `just deploy` to take effect
- [ ] Requires SSH access (auth/security changes)
- [ ] Rolling update safe

## Checklist

- [ ] `lib.mkOptionDefault` used for extensible lists (ports, packages)
- [ ] No `:latest` tags (SHA-pinned or versioned)
- [ ] GPU workloads default to Nexus (not Zephyr)
- [ ] Commit messages reference issue number: `(#NNN)`
