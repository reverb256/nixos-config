# Incident Response Plan - NixOS Home Cluster
**Based on**: AstralVibe.ca 6-step framework
**Version**: 1.0
**Last Updated**: 2026-02-07

## Incident Classification

### Severity Levels
| Severity | Definition | Response Time | Escalation |
|----------|-------------|----------------|-------------|
| **Critical** | Security breach, data exfiltration, full system compromise | < 5 minutes | Immediate escalation to cluster admin |
| **High** | Authentication bypass, privilege escalation, DoS attack, mining outage | < 15 minutes | Escalate within 1 hour |
| **Medium** | Configuration issues, non-critical vulnerabilities, partial service degradation | < 1 hour | Escalate within 4 hours |
| **Low** | Information disclosure, security warnings, performance degradation | < 4 hours | Escalate within 24 hours |

### Incident Types
- **Security Incidents**: Unauthorized access, data breaches, malware, phishing
- **Service Incidents**: Downtime, performance degradation, mining failures
- **Infrastructure Incidents**: Hardware failures, network outages, storage issues
- **Compliance Incidents**: Policy violations, audit failures, control failures

## 6-Step Incident Response Process

### Step 1: Detection
**Goal**: Identify and report incidents as quickly as possible

**Detection Mechanisms**:
- Prometheus alerts (CPU/Memory/Disk/GPU thresholds exceeded)
- Fail2Ban logs (SSH attack patterns)
- Mining service logs (hashrate drops, connection failures)
- Network monitoring (bandwidth anomalies, packet loss)
- User reports (security issues, service problems)
- Automated compliance checks (control failures)

**Detection Actions**:
1. Monitor Grafana dashboards for alert triggers
2. Check `journalctl -u <service>` for error patterns
3. Review Fail2Ban status: `fail2ban-client status`
4. Verify mining health: `curl http://127.0.0.1:4068/summary`
5. Confirm Tailscale connectivity: `tailscale ping <host>`
6. Check `/data/@projects/` service health if applicable

**Alerting**:
- Grafana alerting sends to Alertmanager
- Alertmanager forwards to email/Slack (to be configured)
- Critical incidents trigger immediate notification

**KPI**: Mean Time to Detection (MTTD) < 5 minutes

---

### Step 2: Assessment
**Goal**: Determine impact, scope, and appropriate response

**Assessment Questions**:
1. What happened? (incident type, affected systems)
2. When did it start? (timeline from logs)
3. What's the impact? (affected services, data at risk)
4. Who's affected? (user impact, project availability)
5. Is it contained? (spread potential, ongoing attacks)

**Assessment Actions**:
1. Gather evidence:
   - System logs: `journalctl --since "2026-02-07 12:00"`
   - Service logs: `journalctl -u <service> --since "1 hour ago"`
   - Network logs: `tailscale status`, `nmap` results
   - Mining logs: `tail -100 /var/log/mining/*.log` (if available)
   - Grafana snapshots: Export dashboard state at detection time
   - Project health: Check `/data/@projects/` integrity

2. Determine scope:
   - Affected hosts: `ping zephyr nexus forge sentry`
   - Affected services: `systemctl status --all | grep failed`
   - Data impact: Check `/data/@projects/` integrity

3. Classify severity: Use classification matrix above
4. Escalate if needed: Contact cluster admin or external support

**Documentation**:
- Create incident ticket in tracking system (or issue tracker)
- Record assessment findings
- Set initial severity level

**KPI**: Assessment completed < 10 minutes after detection

---

### Step 3: Containment
**Goal**: Stop incident spread and limit damage

**Containment Strategies**:

#### Security Incidents
- **Unauthorized access**: Revoke SSH keys, disable affected accounts
  ```bash
  # Revoke SSH key
  rm /root/.ssh/authorized_keys
  systemctl restart sshd
  ```
- **Active attack**: Block attacker IP, enable firewall rules
  ```bash
  # Block IP with Fail2Ban
  fail2ban-client set <jail> banip <attacker_ip>
  ```
- **Malware detected**: Isolate infected host from Tailscale
  ```bash
  # Disable Tailscale on infected host
  tailscale down
  ```

#### Service Incidents
- **Mining failure**: Stop mining, check GPU/CPU health
  ```bash
  systemctl stop lolminer-nvidia
  systemctl stop xmrig
  nvidia-smi
  ```
- **Service crash**: Restart with monitoring, check logs
  ```bash
  systemctl restart <service>
  journalctl -u <service> -f
  ```
- **Network outage**: Verify network configuration, restart NetworkManager
  ```bash
  systemctl restart NetworkManager
  tailscale ping zephyr
  ```

#### Infrastructure Incidents
- **Hardware failure**: Isolate failed component, failover to backup
- **Storage issue**: Mount backup, verify integrity
- **Power issues**: Check UPS, power down gracefully if needed

**Containment Actions**:
1. Stop incident spread: Disconnect affected systems, block attackers
2. Preserve evidence: Don't reboot, capture system state
3. Minimize impact: Failover to redundant systems if available
4. Document containment: Record all actions taken

**KPI**: Containment completed < 15 minutes after assessment

---

### Step 4: Eradication
**Goal**: Remove root cause and ensure no remnants

**Eradication Actions**:

#### Security Incidents
- **Unauthorized access**:
  1. Identify entry point (SSH, VPN, service exploit)
  2. Close vulnerability: Update packages, patch config
  3. Rotate compromised credentials: Regenerate age keys, SSH keys
  4. Remove attacker tools: Find and delete malicious files
  5. Verify removal: Scan for backdoors, check logs

- **Malware**:
  1. Quarantine affected systems: Disconnect from network
  2. Run malware scan: Use trusted antivirus tools
  3. Remove malware: Delete infected files, clean system
  4. Verify clean: Re-scan, check for persistence mechanisms

#### Service/Infrastructure Incidents
- **Configuration error**:
  1. Identify misconfiguration: Review git diff, check logs
  2. Apply fix: Update configuration in `/etc/nixos/`
  3. Deploy fix: `sudo nixos-rebuild switch`
  4. Verify fix: Confirm service is healthy

- **Hardware failure**:
  1. Identify failed component: Use diagnostics (nvidia-smi, smartctl)
  2. Replace/repair component: Physical replacement or vendor support
  3. Verify fix: Test replacement, monitor health

**Eradication Actions**:
1. Remove root cause: Fix vulnerability, replace hardware, correct config
2. Verify removal: Check logs, scan for remnants
3. Test systems: Ensure no recurrence, verify fix
4. Document eradication: Record all actions taken

**KPI**: Eradication completed < 30 minutes after containment

---

### Step 5: Recovery
**Goal**: Restore normal operations with confidence

**Recovery Actions**:

#### System Recovery
1. **Restore affected systems**:
   - Reboot if needed: `sudo systemctl reboot`
   - Restore from backup: Use BorgBackup if corruption occurred
   - Verify integrity: Check `/data/@projects/` files, system logs

2. **Restore services**:
   - Start all services: `sudo systemctl start <service>`
   - Verify health: Check Grafana dashboards, service status
   - Monitor for recurrence: Watch logs, alerts

3. **Restore access**:
   - Re-enable SSH: Restore authorized keys
   - Reconnect VPN: `tailscale up`
   - Verify connectivity: `ping`, `ssh` to all hosts

#### Data Recovery
1. **Verify data integrity**:
   - Check `/data/@projects/` directories
   - Verify backups are current: `borgmatic list`
   - Test project access: `curl http://localhost:<port>/health`

2. **Restore from backup** (if needed):
   ```bash
   # List backups
   borgmatic list

   # Restore specific backup
   borgmatic extract --archive <archive_id> /data/@projects/
   ```

3. **Validate restored data**:
   - Check file permissions
   - Verify project functionality
   - Confirm no data loss

**Recovery Actions**:
1. Restore systems to normal operation
2. Verify all services are healthy
3. Confirm data integrity
4. Monitor for recurrence
5. Document recovery: Record all actions taken

**KPI**: Recovery completed < 1 hour after eradication

---

### Step 6: Lessons Learned
**Goal**: Prevent recurrence, improve response capabilities

**Post-Incident Analysis**:
1. **Timeline reconstruction**:
   - When did incident start?
   - When was it detected?
   - How long to contain/eradicate/recover?
   - What was the MTTD/MTTR?

2. **Root cause analysis**:
   - What was the primary cause?
   - What contributing factors existed?
   - Were controls ineffective or missing?
   - What assumptions were wrong?

3. **Impact assessment**:
   - What systems/services were affected?
   - What was the duration of impact?
   - What was the data/system impact?
   - What was the business/user impact?

4. **Response effectiveness**:
   - What worked well?
   - What didn't work?
   - What tools/processes were missing?
   - What communication issues occurred?

5. **Preventive actions**:
   - What controls need to be added/updated?
   - What monitoring needs improvement?
   - What training is needed?
   - What documentation updates are required?

**Documentation Requirements**:
1. Create incident report:
   ```markdown
   # Incident Report: [INCIDENT_ID]
   - **Date**: 2026-02-07
   - **Severity**: Critical/High/Medium/Low
   - **Type**: Security/Service/Infrastructure/Compliance
   - **Summary**: [2-3 sentence description]
   - **Timeline**: [Detection → Assessment → Containment → Eradication → Recovery]
   - **Root Cause**: [Primary cause]
   - **Impact**: [Systems/data/users affected]
   - **Actions Taken**: [Containment, eradication, recovery]
   - **MTTD**: [Time to detection]
   - **MTTR**: [Time to resolution]
   - **Lessons Learned**: [What went well, what didn't]
   - **Preventive Actions**: [What will be done to prevent recurrence]
   ```

2. Update documentation:
   - Update SECURITY_CONTROL_MATRIX.md with new controls
   - Update INCIDENT_RESPONSE_PLAN.md with lessons learned
   - Update SECURITY_POLICY.md if policy changes needed

3. Implement preventive actions:
   - Add/fix controls identified in analysis
   - Update monitoring/alerting if detection was late
   - Update procedures if response was ineffective

**Continuous Improvement**:
- Review incident reports monthly
- Identify patterns in incidents
- Update response procedures based on findings
- Conduct incident response drills quarterly

**KPI**: Lessons learned documented < 24 hours after recovery

## Communication Procedures

### Internal Communication
- **During incident**: Use internal messaging (Tailscale chat, internal communication tools)
- **Status updates**: Every 30 minutes for critical incidents, hourly for high
- **Resolution**: Notify all stakeholders when resolved

### External Communication
- **Security incidents**: Consider privacy implications before disclosure
- **Service outages**: Notify project stakeholders if `/data/@projects/` affected
- **Data breaches**: Follow legal requirements (if applicable)

## Escalation Matrix
| Current Severity | Current Handler | Criteria for Escalation | Escalation To |
|------------------|------------------|-------------------------|-----------------|
| Low | On-call staff | Not resolved in 4 hours | Senior admin |
| Medium | On-call staff | Not resolved in 1 hour | Senior admin |
| High | Senior admin | Not resolved in 15 minutes | Cluster owner |
| Critical | Cluster owner | Immediate escalation required | All stakeholders |

## Contact Information
- **Cluster Admin**: j_kro
- **Tailscale Mesh**: 100.x.x.x network for internal communication
- **Emergency Contact**: To be defined
- **Vendor Support**: To be defined for hardware/network issues

## Testing & Drills

### Incident Response Testing
- **Frequency**: Quarterly
- **Scenario**: Simulated security incident (e.g., unauthorized access attempt)
- **Goals**: Test detection, assessment, containment, eradication, recovery
- **Documentation**: Record response times, identify gaps

### Tabletop Exercises
- **Frequency**: Semi-annually
- **Format**: Walkthrough of incident scenarios without actual execution
- **Goals**: Test decision-making, communication, escalation
- **Documentation**: Identify process improvements

## Appendix: Quick Reference

### Detection Commands
```bash
# Check service status
systemctl status --all | grep failed

# Check recent logs
journalctl --since "1 hour ago" -p err

# Check Fail2Ban
fail2ban-client status

# Check mining health
curl http://127.0.0.1:4068/summary
curl http://127.0.0.1:8081/summary

# Check network
tailscale ping zephyr
ping 10.1.1.1
```

### Containment Commands
```bash
# Block IP with Fail2Ban
fail2ban-client set sshd banip <IP>

# Stop all mining services
systemctl stop lolminer-nvidia xmrig

# Disconnect Tailscale
tailscale down

# Disable SSH
systemctl stop sshd
```

### Recovery Commands
```bash
# Restart services
systemctl restart <service>

# Rebuild and deploy
cd /etc/nixos
sudo nixos-rebuild switch

# Restore from backup
borgmatic list
borgmatic extract --archive <archive_id>

# Reconnect Tailscale
tailscale up
```

---

**Document Owner**: j_kro
**Version**: 1.0
**Next Review**: 90 days (2026-05-07)
**Approval**: To be signed after first incident drill
