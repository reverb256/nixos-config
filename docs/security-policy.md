# Security Policy - NixOS Cluster

**Last Updated:** 2026-02-07
**Version:** 2.0 (Enhanced with OWASP/ISO compliance framework)

## 1. Overview

This document defines the security policies and procedures for the NixOS cluster infrastructure. All users and administrators must adhere to these policies.

## 2. User Access Policy

### 2.1 Principle of Least Privilege
- Users receive minimum permissions required for their role
- sudo access is granted on a per-command basis
- Passwordless sudo for j_kro (YubiKey/passkey planned)

### 2.2 Service Accounts
- All services run as dedicated non-root users
- Service users have no login shell
- Service users have no sudo access
- Lobster user (AI services): No docker, no sudo, no wheel

### 2.3 Password Policy
- No password-based SSH authentication (keys only)
- Passwordless sudo for j_kro (YubiKey/passkey planned)
- Complex passwords (16+ characters) where required
- 2FA recommended for sensitive operations

## 3. Service Security

### 3.1 Mining Services
- Run as dedicated `mining` user (NOT root)
- Strict systemd sandboxing enabled (NoNewPrivileges, ProtectSystem)
- CAP_SYS_ADMIN required for GPU power management (documented security tradeoff)
- API ports only accessible from localhost (127.0.0.1)
- GPU access via video/render groups only

### 3.2 AI Services (OpenClaw)
- Containerized with bridge networking (NOT host network)
- Bound to localhost only (127.0.0.1)
- Nginx reverse proxy for external access
- Rate limiting enabled (10 req/sec, burst 20)
- Fail2Ban protection enabled

### 3.3 Container Security
- No privileged containers
- cap-drop ALL by default
- read-only root filesystem where possible
- Health monitoring with auto-restart

## 4. Network Security

### 4.1 Firewall Rules
- Default: DENY all incoming connections
- Only explicitly allowed ports are open
- Services bound to localhost where possible
- Tailscale VPN for internal cluster communication

### 4.2 Fail2Ban Configuration
- SSH protection: 3 retries, 1-hour ban
- OpenClaw protection: 5 retries, 30-minute ban
- Trusted IPs excluded from bans:
  - localhost (127.0.0.1)
  - Cluster network (10.1.1.0/24)
  - All Tailscale IPs

### 4.3 VPN Security
- All nodes connected via Tailscale mesh VPN
- Subnet routing enabled for 10.1.1.0/24
- Magic DNS enabled
- Exit node configured on zephyr only

## 5. Data Protection

### 5.1 Encryption
- Secrets managed via Agenix (age encryption)
- No plaintext secrets in configuration
- TLS required for all external communications
- LUKS full disk encryption recommended

### 5.2 Backup Policy
- Daily automated backups via BorgBackup
- 7 daily, 4 weekly, 12 monthly, 5 yearly retention
- Encrypted backups with age
- Off-site storage required

### 5.3 Sensitive Data
- API keys in /run/agenix/ only
- No secrets in environment variables (except OpenClaw which uses env vars as documented)
- No credentials in logs or error messages

## 6. Kernel Security

### 6.1 Mitigations
- CPU mitigations ENABLED by default
- Performance impact accepted for security
- May be disabled per-host for gaming/mining (documented)

### 6.2 Kernel Parameters
- `fsync.enable=1` for gaming performance
- `amd_pstate=active` for CPU optimization
- No security-critical parameters disabled

## 7. Monitoring and Alerting

### 7.1 Prometheus + Grafana
- CPU usage monitoring (alert at 80%)
- Memory usage monitoring (alert at 90%)
- Disk usage monitoring (alert at 90%)
- Service health checks every 15s

### 7.2 Logging
- All services log to systemd journal
- Grafana dashboards for visualization
- Retention per systemd configuration

## 8. Incident Response

### 8.1 Detection
- Monitor Grafana dashboards daily
- Review Fail2Ban logs weekly
- Check mining service logs weekly

### 8.2 Response Procedures
1. Isolate affected system from network
2. Identify attack vector
3. Patch vulnerability
4. Restore from backup if necessary
5. Document incident and lessons learned

### 8.3 Contact
- Primary: j_kro
- Emergency: Tailscale mesh for cluster communication

## 9. Compliance

### 9.1 Security Audits
- Monthly configuration review
- Quarterly penetration testing recommended
- Annual security policy review

### 9.2 Vulnerability Management
- Critical vulnerabilities: Patch within 24 hours
- High vulnerabilities: Patch within 72 hours
- Medium vulnerabilities: Patch within 2 weeks
- Low vulnerabilities: Patch within 30 days

## 10. Appendix

### A. Service Accounts
| User | Purpose | Groups | Login | Sudo |
|------|---------|--------|-------|------|
 | j_kro | Primary admin | wheel, networkmanager | Yes | Full (YubiKey/passkey planned) |
| mining | Mining services | video, render | No | nvidia-smi only |
| lobster | AI services | lobster | No | None |
| nixbuild | Nix builds | nixbuild | No | None |

### B. Port Reference
| Port | Service | Access | Protection |
|------|---------|--------|------------|
| 22 | SSH | Tailscale only | Fail2Ban |
| 443 | Nginx | Public | Rate limiting |
| 1234 | LM Studio | localhost | None |
| 18789 | OpenClaw | localhost | Fail2Ban |
| 4068 | lolMiner API | localhost | None |
| 8081 | XMRig API | localhost | None |

### C. Useful Commands
```bash
# Check service status
systemctl status openclaw-container-declarative

# View Fail2Ban status
fail2ban-client status

# Check mining logs
journalctl -u lolminer-nvidia -f

# Monitor GPU
nvidia-smi

# View security logs
journalctl -u fail2ban -f
```

---

**Document Owner:** j_kro  
**Review Schedule:** Annual  
**Next Review:** 2027-02-03
