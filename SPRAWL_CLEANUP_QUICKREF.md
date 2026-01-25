# Sprawl Cleanup - Quick Reference

## 🚀 Quick Start

```bash
# Work in the cleanup tree
cd /etc/nixos-cleanup

# Check status
git status

# Make changes and test
sudo nixos-rebuild build --flake .

# Commit progress
git add .
git commit -m "Phase X: Description"
```

## 📋 Most Important Consolidations

### 1. Fish Shell Modules (HIGH PRIORITY)
**Problem:** 5 files, 800+ lines duplicated
**Solution:** Single `modules/fish.nix`

**Key Decision:** Which features to keep?
- Base: Navigation aliases, git commands, starship
- AI: Conditional via `aiAgent` option

### 2. Mining Services (HIGH PRIORITY)
**Problem:** 4 XMRig services with identical config
**Solution:** `mkMiningService` function

**Pattern:**
```nix
mkMiningService = name: threads: {
  systemd.services.${name} = {
    # Parameterized service definition
  };
};
```

### 3. NVIDIA Settings (MEDIUM PRIORITY)
**Problem:** Hardware config in 3 files
**Solution:** Keep only in `configuration.nix`

## 🧪 Testing Commands

```bash
# Build test (safe)
sudo nixos-rebuild build --flake /etc/nixos-cleanup

# Test boot (riskier)
sudo nixos-rebuild test --flake /etc/nixos-cleanup

# Full switch (production)
sudo nixos-rebuild switch --flake /etc/nixos-cleanup
```

## ⚠️ Risk Areas

### High Risk
- Fish shell changes (affects user experience)
- Mining service refactoring (affects automation)
- SSH configuration (affects remote access)

### Medium Risk
- Main config refactoring
- Module splitting

### Low Risk
- Dead code removal
- Import consolidation

## 📊 Progress Tracking

| Phase | Status | Savings | Risk |
|-------|--------|---------|------|
| 1. Dead Code | ⏳ Ready | ~124 lines | Low |
| 2. Consolidation | ⏳ Pending | ~475 lines | Medium |
| 3. Restructuring | ⏳ Pending | ~600 lines | Medium-High |

## 🎯 Success Criteria

- [ ] Build passes without errors
- [ ] All services start: `systemctl status <service>`
- [ ] Mining works: smart pause during gaming
- [ ] SSH access maintained
- [ ] No performance degradation

## 🚨 Emergency Rollback

```bash
# Switch back to main config
cd /etc/nixos
sudo nixos-rebuild switch --flake .
```

## 📚 Documentation

- `SPRAWL_CLEANUP_IMPLEMENTATION.md` - Full implementation guide
- `SPRAWL_CLEANUP_PROGRESS.md` - Daily progress tracker
- `AGENTS.md` - Current system documentation (needs updating)

## 🔗 Useful Commands

```bash
# Check worktree status
git worktree list

# Compare with main branch
git diff fix-repeated-attributes

# View changes
git log --oneline

# Check service status
systemctl status xmrig* lolminer-nvidia
```

---

**Remember:** Test frequently, commit often, rollback ready!