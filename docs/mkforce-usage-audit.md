# mkForce Usage Audit and Guidelines

## Summary
This document audits all `mkForce` usage in the NixOS configuration and provides guidelines for when to use it.

## Current Usage Statistics
- **Total mkForce occurrences:** 80+
- **Categories:** System modules, services, hardware, virtualization

## When to Use mkForce

### ✅ Appropriate Use Cases

1. **Overriding NixOS Defaults**
   - When NixOS module has a conflicting default
   - Example: `sudo.enable = lib.mkForce false` (replacing with sudo-rs)

2. **Security-Critical Overrides**
   - When security requires explicit value
   - Example: Sysctl hardening in `vm-tuning.nix`

3. **Preventing Module Conflicts**
   - When two modules set same option with incompatible values
   - Example: Container runtime configuration

### ❌ Avoid mkForce When

1. **Appending to Lists**
   - Use `lib.mkOptionDefault` instead
   - Example: Firewall ports, packages

2. **Merging Attrsets**
   - Use `lib.mkOptionDefault` or `//` operator
   - Example: systemd services, environment variables

## Critical mkForce Locations

### Security Module
```nix
# modules/system/security.nix:150
security.sudo.enable = lib.mkForce false;  # ✅ GOOD: Replacing with sudo-rs
```

### VM Tuning Module
```nix
# modules/system/vm-tuning.nix
"vm.overcommit_memory" = lib.mkForce 0;  # ✅ GOOD: Security-critical sysctl
"vm.swappiness" = lib.mkForce 40;         # ✅ GOOD: Performance tuning
```

### Distributed Builds
```nix
# modules/system/distributed-builds.nix:17-45
nix.settings = {
  require-sigs = lib.mkForce false;       # ⚠️ REVIEW: Security implication
  trusted-users = lib.mkForce ["root" "*" "@wheel"];  # ⚠️ REVIEW: Very permissive
};
```

## Recommendations

### High Priority
1. **Audit distributed-builds.nix** - Consider if `trusted-users = "*"` is necessary
2. **Document security overrides** - Add comments explaining why mkForce is needed
3. **Review vm-tuning.nix** - Ensure all mkForce are still necessary

### Medium Priority
4. **Consolidate firewall rules** - Reduce need for mkForce in networking modules
5. **Refactor service modules** - Use mkOptionDefault where possible

## Audit Checklist

For each `mkForce` occurrence, ask:
- [ ] Is this overriding a NixOS default?
- [ ] Is this security-critical?
- [ ] Is there a comment explaining why?
- [ ] Can `mkOptionDefault` be used instead?

## Next Steps

1. Add inline documentation to all mkForce usage
2. Create separate security profile for distributed builds
3. Consider moving some mkForce to host-specific configs
