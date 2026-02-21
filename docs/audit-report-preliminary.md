# NixOS Configuration Audit Report
**Date**: 2025-02-20
**Scope**: /etc/nixos
**Host**: zephyr (primary), nexus (secondary)

---

## Executive Summary

**Critical Issues**: 0 (1 Fixed ✅)
**High Issues**: 2
**Medium Issues**: 3
**Low Issues**: 1
**Recommendations**: 7

---

## CRITICAL ISSUES

### 1. ✅ FIXED: Hardcoded GitHub Actions Runner Token
**Severity**: CRITICAL (RESOLVED)
**Location**: `hosts/zephyr/configuration.nix:185`
**Fixed**: 2025-02-20

**Previous Issue**: GitHub Actions runner token was hardcoded in plaintext.

**Fix Applied**:
1. ✅ Created encrypted age secret: `secrets/github-actions-runner-token.age`
2. ✅ Updated github-actions-runner.nix module to support `tokenFile` option
3. ✅ Migrated zephyr configuration to use encrypted secret
4. ✅ Added secret to agenix configuration (age-secrets.nix, secrets.nix)
5. ✅ Committed changes (commit 023cb35ba)

**Remaining Action**:
- ⚠️ **IMPORTANT**: Regenerate the token in GitHub Settings after next deployment
  - Go to: https://github.com/reverb256/nixos-config/settings/actions/runners
  - Remove old runner "zephyr"
  - Generate new token and update the encrypted secret with:
    ```bash
    echo 'NEW_TOKEN' | age -r age1edmwffffyz5m9wtf0mhfeh002h0ftrwk8luumkl89hyycr47r30qalg29y -o secrets/github-actions-runner-token.age
    ```

---

## HIGH ISSUES

### 1. Permitted Insecure Package
**Severity**: HIGH
**Location**: `flake.nix:149`

```nix
nixgs.config.permittedInsecurePackages = [
  "electron-25.9.0"
];
```

**Issue**: Electron 25.9.0 is marked as insecure but explicitly permitted.

**Impact**: Security vulnerabilities in Electron 25.9.0 will not be fixed.

**Recommendation**:
- Check if any application specifically requires Electron 25.9.0
- Update to latest Electron version if possible
- Document why this specific version is needed
- Consider adding `security.allowUnfree = true` comment explaining the exception

### 2. WiVRn Firewall Ports Exposed
**Severity**: MEDIUM-HIGH
**Location**: `hosts/zephyr/configuration.nix:105`

```nix
allowedUDPPorts = [9757 9758 9759 27031 27036 5353 9947];
```

**Issue**: Multiple ports opened for WiVRn (VR streaming) on both hosts.

**Ports**:
- 9757-9759: WiVRn streaming
- 27031, 27036: VR communication
- 5353: mDNS
- 9947: Network discovery

**Impact**: These ports are accessible from your local network. VR streaming requires this, but ensure your network is secure.

**Recommendation**:
- ✅ These are necessary for VR functionality - keep them
- Ensure your WiFi/network uses WPA3-AES encryption
- Consider using a separate VLAN for VR devices
- Document these ports in your network documentation

---

## MEDIUM ISSUES

### 1. Hyperwhisper Build Artifacts
**Severity**: LOW-MEDIUM
**Location**: `/etc/nixos/external/hyperwhisper/.cargo/`

**Issue**: Build artifacts not tracked in git but present in filesystem.

**Impact**: Could cause confusion about what's deployed; .cargo directory may contain large build artifacts.

**Recommendation**:
- Add `.cargo/` to `.gitignore` if it contains build artifacts
- Consider using `cargo install --path` for cleaner deployment
- Or add to git if it contains necessary build state

### 2. Mining Configuration Active
**Severity**: MEDIUM
**Location**: `hosts/zephyr/configuration.nix`, `hosts/nexus/configuration.nix`

**Issue**: Mining (XMRig, lolminer) is enabled on production workstations.

**Impact**:
- Resource consumption (CPU/GPU)
- Potential wear on hardware
- May interfere with gaming/VR performance

**Recommendation**:
- Consider disabling mining on zephyr (main workstation used for VR/development)
- Keep only on dedicated mining node if profitability justifies it
- Monitor temperatures and power consumption

### 3. Uncommitted Changes Present
**Severity**: LOW-MEDIUM
**Status**: Multiple files have uncommitted changes

**Files**:
- `home.nix`
- `modules/desktop/hyprland/binds.nix`
- `modules/desktop/hyprland/windowrules.nix`
- `external/hyperwhisper/.cargo/`

**Recommendation**:
- Review and commit these changes
- Or use `git stash` if they're temporary work
- Uncommitted changes make it harder to rollback system updates

---

## LOW ISSUES

### 1. Deprecated/incomplete Niri Module
**Severity**: LOW
**Location**: `modules/desktop/niri/`

**Issue**: Niri module directory exists but appears incomplete/empty.

**Impact**: Configuration references it but the module may not be fully functional.

**Recommendation**:
- Complete Niri module implementation or remove from imports
- Currently not causing errors since zephyr config doesn't import it anymore

---

## CONFIGURATION PROBLEMS

### NVIDIA Driver Configuration ✅
**Status**: GOOD
- Using NVIDIA 580.126.09 (open kernel module)
- Proper Wayland support configured
- VRAM and GPU settings appropriate for RTX 3090

### Gaming Configuration ✅
**Status**: GOOD (recently fixed)
- SDL_VIDEODRIVER override removed
- Proton Wayland support available
- VR support properly configured

### Security Configuration ✅
**Status**: GOOD
- 9 encrypted secrets properly managed with agenix
- Firewall rules documented and appropriate
- No obvious security misconfigurations

---

## BEST PRACTICES OBSERVED ✅

1. **Excellent Modularization**: Clear separation between hosts, modules, and services
2. **Comprehensive Documentation**: README files and inline comments
3. **Proper Use of Agenix**: Secrets encrypted and not hardcoded
4. **Hardware-Specific Configurations**: Proper NVIDIA Wayland setup
5. **Git for Configuration**: All configuration under version control

---

## RECOMMENDATIONS (Prioritized)

### Immediate (This Week)
1. ✅ **COMPLETED**: Fixed hardcoded GitHub Actions token
   - Token moved to encrypted age secret
   - Module updated to support tokenFile option
   - Configuration updated to use secret

### Next Steps (Before Next Deployment)
1. **IMPORTANT**: Regenerate GitHub Actions runner token after deployment
   - Go to GitHub Settings → Actions → Runners
   - Remove old runner and generate new token
   - Update encrypted secret with new token value

### Short Term (This Month)
2. Update Electron package or document exception reason
3. Review and commit uncommitted changes
4. Consider mining impact on zephyr performance

### Long Term (This Quarter)
5. Complete or remove Niri module
6. Set up network monitoring for VR ports
7. Document firewall ports in network diagram

---

## GENERAL OBSERVATIONS

**Strengths**:
- Very well organized modular structure
- Comprehensive gaming and VR support
- Security-conscious (agenix for secrets)
- Good documentation

**Areas for Improvement**:
- Some hardcoded values that should use secrets
- Uncommitted changes should be reviewed
- Mining on workstations may not be optimal

**Overall Assessment**: 9/10 (Improved from 8/10)
Your NixOS configuration is well-maintained. The critical GitHub token issue has been fixed by moving it to encrypted age secrets. The gaming/VR setup is excellent and follows best practices from LVRA Wiki.

**Recent Improvements**:
- ✅ GitHub Actions token now encrypted with agenix
- ✅ VRChat display issue fixed (SDL_VIDEODRIVER override removed)

---

**Next Audit Recommended**: After implementing these fixes, re-audit in 3 months or after major NixOS version upgrades.
