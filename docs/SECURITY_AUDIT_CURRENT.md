# Security Audit Report - NixOS Distributed Build Cluster
**Generated:** 2026-01-24  
**Scope:** SSH, User Permissions, Firewall, Services, Mining APIs  
**Status:** ⚠️ 7 Critical Findings, 3 High Priority, 4 Medium Priority

---

## 🚨 CRITICAL SECURITY FINDINGS

### 1. SSH Root Login Enabled (CRITICAL)
**Location:** `modules/ssh.nix:10`  
**Issue:** `PermitRootLogin = "yes"` allows direct root SSH access  
**Risk:** Full system compromise if root credentials are exposed  
**Recommendation:** Disable root login, use sudo with keys only
```nix
PermitRootLogin = "no";
```

### 2. Password Authentication Enabled (CRITICAL)
**Location:** `modules/ssh.nix:7-8`  
**Issue:** `PasswordAuthentication = true` and `KbdInteractiveAuthentication = true`  
**Risk:** Brute force attacks, credential stuffing  
**Recommendation:** Disable password auth, enforce key-only authentication
```nix
PasswordAuthentication = false;
KbdInteractiveAuthentication = false;
```

### 3. Passwordless Sudo for Wheel Group (CRITICAL)
**Location:** `modules/users.nix:73`  
**Issue:** `wheelNeedsPassword = false` gives unlimited passwordless sudo  
**Risk:** Any compromised wheel user has full system access  
**Recommendation:** Require password for sudo, limit passwordless to specific commands

### 4. Mining API with Weak Token (HIGH)
**Location:** `modules/mining-config.nix:12`  
**Issue:** Hardcoded HTTP token `"my-secret-token"` in plaintext  
**Risk:** Unauthorized access to mining controls  
**Recommendation:** Use agenix for secret management or generate strong random tokens

### 5. Multiple SSH Keys with Root Access (HIGH)
**Location:** `modules/users.nix:40-47`  
**Issue:** Root SSH keys from multiple hosts/CA systems  
**Risk:** Compromise of any key gives root access to entire cluster  
**Recommendation:** Restrict root access, use individual user keys with proper rotation

### 6. Tailscale VPN Without ACLs (HIGH)
**Location:** `modules/networking-shared.nix:169`  
**Issue:** Tailscale enabled without access control lists  
**Risk:** Unrestricted network access across all connected devices  
**Recommendation:** Configure Tailscale ACLs to restrict access between devices

### 7. Steam Open Firewall (MEDIUM-HIGH)
**Location:** `modules/gaming.nix:218`  
**Issue:** `openFirewall = true` opens all required Steam ports  
**Risk:** Exposes gaming services to network  
**Recommendation:** Specify exact ports needed instead of blanket open

---

## 🔍 DETAILED SECURITY ANALYSIS

### SSH Configuration Analysis
**✅ Strengths:**
- Modern cryptographic algorithms configured
- Strong ciphers (ChaCha20-Poly1305, AES-GCM)
- Post-quantum KEX algorithms supported
- DNS usage disabled for privacy

**❌ Vulnerabilities:**
- Root login permitted (critical)
- Password authentication enabled (critical)
- No connection rate limiting
- No source IP restrictions

### User Permissions Analysis
**✅ Strengths:**
- Dedicated mining system user with restricted shell
- Proper group separation (wheel, video, input)
- SSH keys properly configured for main user

**❌ Vulnerabilities:**
- Passwordless sudo for wheel group (critical)
- Root SSH keys from multiple sources (high)
- Mining user in video/input groups (medium risk)
- No account lockout policies

### Firewall & Network Security
**✅ Strengths:**
- Unbound DNS with DoT encryption
- Analytics blocklist for privacy
- Local network access properly restricted
- No open ports by default

**❌ Vulnerabilities:**
- Steam gaming services open firewall
- Tailscale without ACLs
- Avahi device discovery enabled (potential attack surface)
- No intrusion detection system

### Service Exposure Analysis
**Exposed Services by Host:**
- **Zephyr (10.1.1.110):** SSH (22), Steam ports, WiVRn (9757, UDP range)
- **Nexus (10.1.1.120):** SSH (22) only
- **Forge (10.1.1.130):** SSH (22) only  
- **Sentry (10.1.1.140):** SSH (22) only

**Mining API Ports:**
- **XMRig:** 8081/TCP (localhost only ✅)
- **lolMiner NVIDIA:** 4068/TCP (localhost access ✅)
- **lolMiner AMD:** 4069/TCP (localhost access ✅)

### Mining Security Analysis
**✅ Strengths:**
- Mining APIs properly restricted to localhost
- HTTP authentication with tokens
- Systemd service isolation
- Dedicated mining user

**❌ Vulnerabilities:**
- Weak/placeholder HTTP token
- No API rate limiting
- Mining logs may contain sensitive data
- No monitoring for unauthorized access attempts

---

## 📋 SECURITY RECOMMENDATIONS

### Immediate Actions (Critical)
1. **Disable SSH Root Login**
   ```nix
   # In modules/ssh.nix
   PermitRootLogin = "no";
   ```

2. **Disable SSH Password Authentication**
   ```nix
   # In modules/ssh.nix  
   PasswordAuthentication = false;
   KbdInteractiveAuthentication = false;
   ```

3. **Fix Passwordless Sudo**
   ```nix
   # In modules/users.nix
   security.sudo.wheelNeedsPassword = true;
   # Keep specific mining commands passwordless if needed
   ```

### High Priority Actions
4. **Secure Mining API Tokens**
   ```nix
   # Use agenix for secrets
   services.mining.xmrig.httpToken = config.age.secrets.xmrig-token.path;
   ```

5. **Configure Tailscale ACLs**
   - Create `~/.config/tailscale/acl.json`
   - Restrict inter-device communication
   - Limit admin access to specific devices

6. **Restrict Root SSH Keys**
   - Remove root SSH keys from user config
   - Use individual user accounts with sudo
   - Implement key rotation policy

### Medium Priority Actions
7. **Add SSH Hardening**
   ```nix
   # In modules/ssh.nix
   settings = {
     MaxAuthTries = 3;
     ClientAliveInterval = 300;
     ClientAliveCountMax = 2;
     AllowUsers = ["j_kro"]; # Restrict to specific users
   };
   ```

8. **Implement Firewall Granularity**
   ```nix
   # Instead of openFirewall = true for Steam
   networking.firewall.allowedTCPPorts = [27036 27037];
   networking.firewall.allowedUDPPorts = [27031 27036];
   ```

9. **Add Network Monitoring**
   ```nix
   # Consider adding fail2ban or similar
   services.fail2ban.enable = true;
   ```

10. **Secure Configuration Management**
    - Move sensitive configs to agenix
    - Implement configuration backup/versioning
    - Regular security audits

---

## 🛡️ SECURITY HARDENING PLAN

### Phase 1: Critical Fixes (Week 1)
- [ ] Disable SSH root login
- [ ] Disable password authentication  
- [ ] Fix passwordless sudo
- [ ] Secure mining API tokens

### Phase 2: Network Hardening (Week 2)
- [ ] Configure Tailscale ACLs
- [ ] Restrict SSH keys
- [ ] Implement firewall granularity
- [ ] Add fail2ban

### Phase 3: Monitoring & Maintenance (Week 3)
- [ ] Set up intrusion detection
- [ ] Implement log monitoring
- [ ] Create security update schedule
- [ ] Document security procedures

---

## 📊 SECURITY SCORE

| Category | Current | Target | Status |
|----------|---------|--------|---------|
| SSH Configuration | 3/10 | 9/10 | ❌ Critical |
| User Permissions | 4/10 | 8/10 | ❌ Critical |
| Network Security | 6/10 | 9/10 | ⚠️ Medium |
| Service Security | 7/10 | 9/10 | ⚠️ Medium |
| Mining Security | 6/10 | 9/10 | ⚠️ Medium |
| **Overall Score** | **5.2/10** | **8.8/10** | **❌ Critical** |

---

## 🚨 IMMEDIATE ACTION REQUIRED

**Critical vulnerabilities require immediate attention before production deployment.**

1. SSH configuration poses immediate compromise risk
2. Passwordless sudo provides unlimited privilege escalation
3. Mining API tokens exposed in plaintext
4. Root access keys distributed across cluster

**Recommendation:** Address Critical and High priority findings within 48 hours to prevent security incidents.

---

**Report generated by:** Sisyphus-Junior Security Auditor  
**Next audit recommended:** After implementing Phase 1 fixes  
**Contact:** Review findings with system administrator immediately