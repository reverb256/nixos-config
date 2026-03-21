# Akash Provider Data Retention & Privacy Policy
**Provider**: reverb256.ca
**Version**: 1.0
**Effective Date**: 2026-03-21
**Compliance**: GDPR, CCPA, PIPEDA

---

## Policy Overview

This policy governs the retention, deletion, and handling of tenant data on the reverb256.ca Akash provider infrastructure. Our commitment is to **privacy-first** operations with automatic data cleanup and transparent data handling practices.

---

## Data Classification

### Tenant Data Types
1. **Application Data**: User-generated content, databases, application state
2. **Configuration Data**: Environment variables, secrets, deployment manifests
3. **Log Data**: Application logs, audit trails, access logs
4. **Storage Volumes**: PersistentVolumeClaims, snapshots, backups

### Data Sensitivity Levels
- **Level 1 (Public)**: Non-sensitive application data
- **Level 2 (Internal)**: Application configuration, logs
- **Level 3 (Confidential)**: User data, credentials, secrets
- **Level 4 (Restricted)**: PII, financial data, health information

---

## Retention Periods

### Standard Retention

| Data Type | Retention Period | Deletion Method |
|-----------|-----------------|-----------------|
| Active Lease Volumes | Until lease ends | Tenant-initiated |
| Released PVCs | 7 days | Automated cleanup |
| Namespace Metadata | 30 days after lease | Automated cleanup |
| Application Logs | 7 days | Automated cleanup |
| Audit Logs | 90 days | Automated cleanup |
| Backups | 7 days | Automated cleanup |

### Extended Retention (Upon Request)
Tenants may request extended retention for legitimate purposes:
- **Compliance requirements**: Legal hold, litigation
- **Business continuity**: Disaster recovery testing
- **Data migration**: Transfer to another provider

**Process**: Submit written request to admin@reverb256.ca with justification

---

## Automated Data Cleanup

### Cleanup Schedule

**Daily CronJob** (runs at midnight UTC):
```yaml
schedule: "0 0 * * *"
job: volume-cleanup
namespace: akash-services
```

### Cleanup Process

**Step 1: Identify Released Volumes**
```bash
# Find all PVCs with status: Released
kubectl get pvc -n lease-* --all-namespaces
```

**Step 2: Verify Age**
```bash
# Check if released > 7 days ago
if [ age_days -gt 7 ]; then
  # Safe to delete
fi
```

**Step 3: Secure Deletion**
```bash
# Delete PVC
kubectl delete pvc -n <namespace> <pvc-name>

# Note: Data is not overwritten (see Data Sanitization below)
# For high-sensitivity data, implement secure deletion
```

**Step 4: Audit Log**
```bash
# Log all deletions with timestamp, namespace, PVC, and justification
echo "$(date) DELETED $namespace/$pvc age=$age_days" >> /var/log/akash/volume-cleanup.log
```

### Cleanup Exclusions

**Excluded from Automatic Deletion**:
- Volumes under active legal hold
- Volumes with explicit retention extension request
- Volumes in active dispute resolution
- Backup snapshots (retained per backup policy)

---

## Data Sanitization

### Current Implementation
- **Filesystem deletion**: Standard Kubernetes `delete pvc` operation
- **Block device**: Data remains on storage device until overwritten
- **Provider responsibility**: Ensure data is inaccessible after deletion

### Recommended Enhancements (High-Security Deployments)

**Option 1: Volume Encryption**
```yaml
# Encrypt volumes at rest (LUKS on provider nodes)
# Even if data remnants exist, they're encrypted
apiVersion: v1
kind: StorageClass
metadata:
  name: encrypted-beta2
provisioner: local
parameters:
  encrypted: "true"
  cipher: "aes-xts-plain64"
  keySize: 256
```

**Option 2: Secure Wipe**
```bash
# Before volume deletion (manual process)
shred -vfz -n 3 /dev/mapper/volume-data
# Only for high-sensitivity data
```

**Option 3: Zero-Fill Reinitialization**
```bash
# After volume deletion, before reusing
dd if=/dev/zero of=/dev/sdX bs=1M count=100
```

---

## Tenant Data Rights

### Right to Access
Tenants can access their data during active lease:
- Direct pod/container access
- Volume mounting to external systems
- Backup/restore operations

### Right to Export
Tenants may export data before lease termination:
- Tooling: `kubectl cp`, `kubectl exec`, SFTP
- Format: Raw, tarball, custom format
- Timeline: Until lease ends

### Right to Be Forgotten (GDPR Article 17)
**Process**:
1. Tenant submits deletion request: `data-deletion@reverb256.ca`
2. Provider verifies identity (blockchain signature or lease key)
3. Provider deletes all copies:
   - Primary volumes
   - Backup snapshots
   - Log entries containing PII
4. Provider confirms deletion within 30 days
5. Tenant receives deletion certificate

**Exceptions**:
- Legal hold prevents deletion
- Regulatory requirement to retain
- Other active tenants' data intermingled

### Right to Data Portability (GDPR Article 20)
**Process**:
1. Tenant requests data export: `data-export@reverb256.ca`
2. Provider provides options:
   - Direct volume access
   - Encrypted download link
   - Transfer to another provider
3. Timeline: Within 30 days of request
4. Format: Machine-readable standard format

---

## Data Breach Notification

### Notification Triggers
Provider will notify tenants within 72 hours of discovering:
- Unauthorized access to tenant data
- Accidental data disclosure
- Data loss or corruption
- Security incident affecting tenant confidentiality

### Notification Channels
- **Email**: admin@reverb256.ca
- **Blockchain**: On-chain attestation with incident details
- **GitHub**: Public disclosure (if public data affected)

### Notification Contents
- Nature and scope of breach
- Data types affected
- Timeline of incident
- Mitigation steps taken
- Tenant remediation options

---

## Provider Access to Tenant Data

### Allowed Access (For Operations)

**System Administration**:
- **Purpose**: Cluster maintenance, troubleshooting, capacity planning
- **Access Type**: Read-only metadata (namespace names, resource usage)
- **Approval**: No approval needed (operational data)

**Security Monitoring**:
- **Purpose**: Threat detection, intrusion prevention, audit
- **Access Type**: Falco rule alerts, log aggregation
- **Approval**: No approval needed (automated monitoring)

**Backup/Restore**:
- **Purpose**: Disaster recovery, data protection
- **Access Type**: Volume snapshots, backup storage
- **Approval**: No approval needed (automated backups)

### Prohibited Access

**Strictly Prohibited**:
- ❌ Reading tenant application data without explicit consent
- ❌ Accessing tenant secrets/credentials
- ❌ Modifying tenant applications without authorization
- ❌ Selling or monetizing tenant data
- ❌ Analyzing tenant proprietary code/algorithms

**Exceptions**: Only with tenant's explicit written consent or legal requirement

---

## Audit Trail

### What We Log

**Provider Operations**:
- Lease creation/termination
- Resource allocation/deallocation
- Namespace creation/deletion
- Volume provisioning/deletion

**Security Events**:
- Failed authentication attempts
- Policy violations (Falco alerts)
- Network anomalies
- Privilege escalation attempts

**Data Access**:
- Volume access (by provider)
- Backup/restore operations
- Export requests
- Deletion operations

### Log Retention
- **Operational logs**: 90 days
- **Security logs**: 1 year
- **Audit trails**: 7 years (compliance)

### Log Access
- **Tenant access**: To their own logs only
- **Provider access**: All logs (operational necessity)
- **Auditor access**: Upon request with proper authorization

---

## Compliance Framework Alignment

### GDPR (General Data Protection Regulation)
- ✅ **Article 15**: Right of access
- ✅ **Article 17**: Right to erasure (right to be forgotten)
- ✅ **Article 20**: Right to data portability
- ✅ **Article 25**: Data protection by design and default
- ✅ **Article 32**: Security of processing
- ✅ **Article 33**: Notification of personal data breach

### CCPA (California Consumer Privacy Act)
- ✅ **Right to know**: Access to personal information
- ✅ **Right to delete**: Deletion of personal information
- ✅ **Right to portability**: Data transfer capabilities
- ✅ **Opt-out**: Sale of personal information (not applicable)

### PIPEDA (Personal Information Protection and Electronic Documents Act)
- ✅ **Collection limitation**: Limited to lease requirements
- ✅ **Use, disclosure, and retention**: Defined in this policy
- ✅ **Safeguards**: Security measures implemented
- ✅ **Individual access**: Tenant can request access
- ✅ **Challenging compliance**: Verification mechanisms in place

---

## Incident Response

### Data Breach Response Plan

**Step 1: Identification** (0-24 hours)
- Detect breach via Falco alerts, monitoring, or tenant report
- Activate incident response team
- Initial assessment of scope and impact

**Step 2: Containment** (24-48 hours)
- Isolate affected systems
- Preserve evidence (forensic capture)
- Prevent further unauthorized access

**Step 3: Notification** (48-72 hours)
- Notify affected tenants
- Notify regulatory bodies (if required)
- Public disclosure (if public data affected)

**Step 4: Remediation** (Ongoing)
- Patch vulnerabilities
- Restore from backups
- Implement preventive measures

**Step 5: Post-Incident Review** (Within 30 days)
- Root cause analysis
- Process improvements
- Documentation updates

---

## Contact Information

**Data Protection Officer**: admin@reverb256.ca
**Security Team**: security@reverb256.ca
**Provider Address**: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
**Provider Domain**: provider.reverb256.ca

**To Exercise Rights**:
- Data access: data-access@reverb256.ca
- Data deletion: data-deletion@reverb256.ca
- Data export: data-export@reverb256.ca
- Policy questions: policy@reverb256.ca

---

## Policy Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-21 | Initial policy publication |

---

**Next Review**: 2026-06-21 (quarterly review)
**Approval**: Provider owner: admin@reverb256.ca
**Status**: ✅ Active and Enforced
