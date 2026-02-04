# Sprawl Cleanup TODO

## Phase 1: Dead Code Elimination (Start Here)

- [ ] Import `nvidia-optimization-services.nix` in configuration.nix
- [ ] Remove duplicate sudo rules from configuration.nix (lines 14-44)
- [ ] Remove duplicate NVIDIA hardware settings from gaming.nix and common/default.nix
- [ ] Test build: `sudo nixos-rebuild build --flake /etc/nixos-cleanup`
- [ ] Commit Phase 1: `git commit -m "Phase 1: Dead code elimination"`

## Phase 2: High-Impact Consolidation (Next)

- [ ] Create `modules/fish.nix` consolidating all Fish configurations
- [ ] Implement `mkMiningService` function in mining.nix
- [ ] Consolidate environment variables to environment.nix only
- [ ] Test all services (Fish, mining, NVIDIA)
- [ ] Commit Phase 2: `git commit -m "Phase 2: High-impact consolidation"`

## Phase 3: Module Restructuring (Final)

- [ ] Split networking.nix into domain-specific modules
- [ ] Create dedicated ssh.nix module
- [ ] Refactor configuration.nix to import-only style
- [ ] Full system test and validation
- [ ] Commit Phase 3: `git commit -m "Phase 3: Module restructuring"`

## Validation & Merge

- [ ] Performance benchmark (build times)
- [ ] Service dependency validation
- [ ] Update AGENTS.md and README.md
- [ ] Create merge request to main branch
- [ ] Deploy to production

---

## Risk Mitigation Checklist

- [ ] Backup current working config
- [ ] Test builds after each phase
- [ ] Monitor critical services (mining, SSH, gaming)
- [ ] Keep rollback plan ready
- [ ] Document any issues encountered

---

**Current Status:** Ready for Phase 1
**Estimated Time:** 3-5 days
**Target Savings:** 1,200+ lines