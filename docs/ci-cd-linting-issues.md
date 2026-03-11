# CI/CD Linting Issues Tracking

**Created**: 2026-03-11
**Context**: Task 4 of CI/CD refactoring removed `continue-on-error: true` from linters
**Status**: Active - needs resolution before CI can pass

## Summary

As part of the CI/CD refactoring (Task 4), we removed silent linter failures to enforce code quality. This exposed numerous pre-existing linting issues that must be fixed. CI will now fail until these issues are resolved.

## Current CI Status

| Check | Status | Issues |
|-------|--------|--------|
| `nix flake check` | ❌ FAILING | lolminer-image derivation errors |
| `statix check` | ⚠️ 12+ WARNINGS | Unused code, repeated keys, style issues |
| `deadnix -f` | ⚠️ 5+ WARNINGS | Unused lambda patterns, unused bindings |

---

## Issues by Severity

### CRITICAL (Blockers)

#### 1. Flake Check Failure - lolminer-image Derivation
**Location**: `modules/services/mining/lolminer-image.nix`
**Error Type**: Derivation build failure
**Impact**: Blocks `nix flake check` - entire CI fails

**Details**:
```
error: builder for '/nix/store/...-lolminer-image.drv' failed
```

**Root Cause**: Image build configuration issue (needs investigation)

**Action Required**:
- [ ] Investigate derivation failure
- [ ] Fix image build configuration
- [ ] Verify with `nix build .#lolminer-image`

---

### IMPORTANT (Code Quality)

#### 2. Statix W04: Unused let bindings
**Count**: Multiple occurrences
**Impact**: Dead code increases maintenance burden

**Affected Files**:
- `modules/services/glitchtip-selfhosted.nix`
- `modules/system/cluster-storage.nix`
- `modules/system/distributed-builds.nix`

**Example**:
```nix
let
  unusedVar = ...;  # W04
in
  actualConfig
```

**Action Required**:
- [ ] Remove unused let bindings
- [ ] Verify no runtime dependencies

---

#### 3. Statix W08: Repeated map keys
**Count**: 2+ occurrences
**Impact**: Later keys overwrite earlier ones (data loss risk)

**Affected Files**:
- `modules/services/glitchtip-selfhosted.nix`

**Example**:
```nix
{
  key = value1;
  key = value2;  # W08 - overwrites value1
}
```

**Action Required**:
- [ ] Review and deduplicate keys
- [ ] Resolve conflicts intentionally

---

#### 4. Statix W10: Unused pattern alternatives
**Count**: 3+ occurrences
**Impact**: Code complexity without benefit

**Affected Files**:
- `modules/system/distributed-builds.nix`
- `modules/system/compute-workload-monitor.nix`

**Example**:
```nix
{
  foo.bar = ...;
  foo.${suffix} = ...;  # W10 - unused alternative
}
```

**Action Required**:
- [ ] Remove unused pattern alternatives
- [ ] Simplify pattern matching

---

#### 5. Deadnix: Unused lambda patterns
**Count**: 3+ occurrences
**Impact**: Misleading code structure

**Affected Files**:
- `modules/system/distributed-builds.nix`
- `modules/system/compute-workload-monitor.nix`

**Example**:
```nix
{ config, pkgs, ... }:  # 'pkgs' unused
{
  # config only used
}
```

**Action Required**:
- [ ] Replace unused patterns with `_` or `...`
- [ ] Example: `{ config, ... }:` instead of `{ config, pkgs, ... }:`

---

### MINOR (Style)

#### 6. Statix W12: Empty let binding
**Count**: 1 occurrence
**Impact**: Code verbosity

**Affected Files**:
- `modules/services/glitchtip-selfhosted.nix`

**Action Required**:
- [ ] Remove empty `let` clauses or add missing bindings

---

#### 7. Statix W20: Legacy sequence notation
**Count**: Multiple occurrences
**Impact**: Non-idiomatic Nix

**Example**:
```nix
[ foo bar ]  # W20 - prefer list syntax
```

**Action Required**:
- [ ] Update to modern Nix syntax where applicable

---

## Resolution Plan

### Phase 1: Fix Critical Blockers (Priority: HIGH)
1. ✅ Create this tracking document
2. [ ] Fix `lolminer-image` derivation
3. [ ] Verify `nix flake check` passes

### Phase 2: Fix Important Issues (Priority: MEDIUM)
4. [ ] Fix statix W04 (unused let bindings)
5. [ ] Fix statix W08 (repeated map keys)
6. [ ] Fix deadnix warnings (unused patterns)

### Phase 3: Clean Up Minor Issues (Priority: LOW)
7. [ ] Fix statix W12 (empty let binding)
8. [ ] Fix statix W20 (legacy notation)

### Phase 4: Verification
9. [ ] Run full CI pipeline
10. [ ] Verify all checks pass
11. [ ] Update CI/CD implementation plan

---

## Commands for Local Testing

```bash
# Test flake check
nix flake check

# Run statix locally
nix shell nixpkgs#statix --command statix check .

# Run deadnix locally
nix shell nixpkgs#deadnix --command deadnix -f .

# Build specific failing derivation
nix build .#lolminer-image
```

---

## Related Documentation

- `docs/CI-CD-IMPLEMENTATION-PLAN.md` - Full CI/CD refactoring roadmap
- `.github/workflows/ci.yml` - CI configuration (now enforces these checks)
- `AGENTS.md` - Agent patterns for code quality

---

## Notes

- **Decision**: We chose Option B (keep strict CI) over reverting
- **Rationale**: Strict linting prevents technical debt accumulation
- **Trade-off**: CI will fail until issues are resolved (acceptable for feature branch)
- **Next Step**: Triage and fix issues in priority order

**Last Updated**: 2026-03-11
