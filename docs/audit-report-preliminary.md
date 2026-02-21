# NixOS Configuration Audit Report
**Date**: 2025-02-20
**Scope**: /etc/nixos
**Host**: zephyr (primary), nexus (secondary)

---

## Executive Summary

**Critical Issues**: 1
**High Issues**: 2
**Medium Issues**: 3
**Low Issues**: 1
**Recommendations**: 7

---

## CRITICAL ISSUES

### 1. Hardcoded GitHub Actions Runner Token ⚠️
**Severity**: CRITICAL
**Location**: `hosts/zephyr/configuration.nix:185`

```nix
token = "A646A7TUAS6J5QKTBIELDDLJS7MVQ";
```

**Issue**: GitHub Actions runner token is hardcoded in plaintext. This token grants access to create/modify workflows in your repository.

**Impact**: If this token is committed to a public repository or shared, anyone can use it to execute arbitrary code in your GitHub Actions workflows.

**Recommendation**:
1. Immediately regenerate the token: GitHub → Settings → Actions → Runners → Token
2. Move token to encrypted secrets: `agenix` or `sops`
3. Update configuration to read from secrets:
   ```nix
   token = config.age.secrets.github-actions-runner-token;
   ```
4. Add `/etc/nixos/secrets/github-actions-runner-token.age` to gitignore
5. Force rotate the token in GitHub repo settings

**Files to Modify**:
- `/etc/nixos/modules/services/github-actions-runner.nix` - Add secrets option
- `/etc/nixos/secrets.nix` - Add secret definition
- `/etc/nixos/hosts/zephyr/configuration.nix` - Use secret instead of hardcoded value

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
1. ✅ **URGENT**: Fix hardcoded GitHub Actions token
   - Use agenix to encrypt the token
   - Regenerate the token after

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

**Overall Assessment**: 8/10
Your NixOS configuration is well-maintained with only a few critical issues (the GitHub token being most urgent). The gaming/VR setup is excellent and follows best practices from LVRA Wiki.

---

**Next Audit Recommended**: After implementing these fixes, re-audit in 3 months or after major NixOS version upgrades.
