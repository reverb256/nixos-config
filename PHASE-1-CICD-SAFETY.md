# Phase 1: CI/CD Safety Foundation

**Status:** IN PROGRESS
**Created:** 2026-04-23 | **Updated:** 2026-04-23
**Owner:** j_kro

## Executive Summary

Phase 1 establishes CI/CD guardrails to prevent broken deployments. The focus is on Garnix for flake validation, selective input updates, and branch protection.

## Objectives

1. **Garnix Integration** - Validate all flakes before merge
2. **Selective Updates** - Avoid nuclear `nix flake update`
3. **Branch Protection** - Require review + CI checks

## Garnix Setup

### Target Repositories (8)

| Repo | Path | garnix.nix Status | Priority |
|------|------|-------------------|----------|
| hermes-agent | /data/projects/own/hermes-agent | ✅ EXISTS | P0 |
| ai-inference-gateway | /data/projects/own/ai-inference-gateway | ❌ MISSING | P0 |
| knowledge-fabric | /data/projects/own/knowledge-fabric | ❌ MISSING | P1 |
| compute-market | /data/projects/own/compute-market | ❌ MISSING | P1 |
| llama-cpp-turboquant | /data/projects/llama-cpp-turboquant | ❌ MISSING | P1 |
| mcp-registry | /data/projects/own/mcp-registry | ❌ MISSING | P2 |
| caddy-ingress | /data/projects/own/caddy-ingress | ❌ MISSING | P2 |
| searxng-cluster | (in /etc/nixos/kubernetes/) | ❌ N/A | P2 |

### garnix.nix Template

```nix
{
  description = "Hermes Agent - Garnix CI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystemMap (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        # Default package (usually the main app)
        packages.default = self.packages.${system}.<main-package>;

        # CI checks
        checks = {
          # Flake evaluation
          flake-check = pkgs.runCommand "flake-check" {
            nativeBuildInputs = [ pkgs.nix ];
          } ''
            nix flake check ${self} --no-build
            touch $out
          '';

          # Format check (if using nixfmt)
          format-check = pkgs.runCommand "format-check" {
            nativeBuildInputs = [ pkgs.nixfmt ];
          } ''
            nixfmt --check ${self}
            touch $out
          '';
        };
      }
    );
}
```

### Implementation Steps

1. **Create garnix.nix** in each repo root
2. **Enable Garnix** on GitHub (Settings → Actions)
3. **Add workflow** (`.github/workflows/garnix.yml`):
   ```yaml
   name: Garnix
   on: [pull_request]
   jobs:
     garnix:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v3
         - uses: cachix/install-nix-action@v22
         - uses: cachix/install-nix-action@v22
           with:
             extra_nix_config: |
               experimental-features = nix-command flakes
         - uses: yaxitech/nix-install-action@v19
           with:
             nix_version: 2.13
         - run: nix build .#checks.x86_64-linux --print-build-logs
   ```

## Selective Flake Updates

### Problem: Nuclear Updates

```bash
# DON'T DO THIS - Updates ALL inputs
nix flake update
```

**Risks:**
- Breaks 8 repos simultaneously
- Hard to roll back
- No per-input testing

### Solution: Selective Updates

```bash
# DO THIS - Update ONE input at a time
nix flake lock update <input-name>

# Examples:
nix flake lock update hermes-agent
nix flake lock update nixpkgs
nix flake lock update ai-gateway
```

### Critical Inputs to Pin

| Input | Current Pin | Update Frequency |
|-------|-------------|------------------|
| hermes-agent | Commit SHA | Monthly (security) |
| nixpkgs | `nixos-unstable` | Weekly (after testing) |
| ai-gateway | Path (no pin) | As needed |
| k3s | Version tag | Quarterly |

### Update Procedure

1. **Create branch**: `git checkout -b update/hermes-agent`
2. **Update single input**: `nix flake lock update hermes-agent`
3. **Test locally**: `nix build .#checks.x86_64-linux`
4. **Commit**: `git commit -am "update: hermes-agent to <commit>"`
5. **PR**: Open PR, wait for Garnix CI
6. **Merge**: After CI passes + review

### Rollback Procedure

```bash
# If update breaks build:
git revert <commit-hash>
nix flake update  # Restore previous lock state
```

## Branch Protection

### GitHub Settings

**Repository → Settings → Branches**

Rule: `main` (and `autoresearch/*`)

| Setting | Value |
|---------|-------|
| Require pull request | ✅ YES |
| Required approvals | 1 |
| Require status checks | ✅ YES |
| Required checks | Garnix |
| Require branches to be up to date | ✅ YES |
| Do not allow bypass | ✅ YES |

### Required Checks

- `Garnix` (flake validation)
- `Tests` (if present)

## Canary Deploy Pattern

### Pattern Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    CANARY DEPLOY FLOW                        │
├─────────────────────────────────────────────────────────────┤
│  1. Create branch: feature/xyz                              │
│  2. Update flake input (selective)                          │
│  3. Test locally: nix build                                  │
│  4. Push: git push origin feature/xyz                       │
│  5. Garnix CI runs automatically                            │
│  6. Create PR: main ← feature/xyz                           │
│  7. Wait for: CI pass + review                              │
│  8. Merge to main                                           │
│  9. Deploy: just deploy <host>                              │
│ 10. Monitor: Check logs, metrics                            │
│ 11. Rollback if needed: git revert + just deploy             │
└─────────────────────────────────────────────────────────────┘
```

### For Cluster Deployments

```bash
# Deploy to single host first (canary)
just deploy zephyr

# Verify: check GPU, mining, AI, gaming
ssh zephyr "nvidia-smi; systemctl status mining"

# If OK: deploy to remaining hosts
just deploy nexus forge sentry
```

## Next Steps

1. ✅ **Phase 0 Complete** - nix-mineral enabled on all hosts
2. ⏳ **Create garnix.nix** for ai-inference-gateway (P0)
3. ⏳ **Enable Garnix CI** on hermes-agent, ai-gateway repos
4. ⏳ **Configure branch protection** on all 8 repos
5. ⏳ **Document rollback procedures** for each repo

## Dependencies

### External
- Garnix: https://github.com/hermes-oss/garnix
- GitHub Actions

### Internal
- Phase 0 complete ✅
- All repos must have flake.nix

## Success Criteria

- ⏳ Garnix CI running on all repos
- ⏳ Selective update workflow documented
- ⏳ Branch protection enabled
- ⏳ Rollback tested on one repo

## References

- **Phase 0:** PHASE-0-SECURITY-BASELINE.md
- **Master Plan:** MASTER-PLAN.md
- **Garnix:** https://github.com/hermes-oss/garnix

---

**Last Updated:** 2026-04-23
**Status:** Phase 0 Complete → Phase 1 In Progress
