# Kubernetes Security Runbook
**Version**: 1.0
**Last Updated**: 2026-03-21
**Cluster**: NixOS 4-node homelab
**Severity Levels**: Critical, High, Medium, Low

---

## Executive Summary

This runbook provides step-by-step procedures for responding to security incidents in the Kubernetes cluster. It covers compromised pods, network policy violations, RBAC issues, and complete security audits.

---

## Table of Contents

1. [Incident Response Framework](#incident-response-framework)
2. [Compromised Pod Procedures](#compromised-pod-procedures)
3. [Network Policy Incidents](#network-policy-incidents)
4. [RBAC & Authorization Issues](#rbac--authorization-issues)
5. [Security Audit Procedures](#security-audit-procedures)
6. [Rollback Procedures](#rollback-procedures)
7. [Post-Incident Analysis](#post-incident-analysis)

---

## Incident Response Framework

### Severity Levels

| Severity | Response Time | Examples |
|----------|---------------|----------|
| **Critical** | < 15 minutes | Active compromise, data exfiltration |
| **High** | < 1 hour | Suspicious activity, policy violations |
| **Medium** | < 4 hours | Configuration errors, access issues |
| **Low** | < 24 hours | Documentation updates, minor issues |

### Incident Response Flow

```
Detection → Triage → Containment → Eradication → Recovery → Post-Mortem
   ↓          ↓         ↓            ↓            ↓            ↓
 Alert    Assess    Isolate     Remove      Restore      Document
          Impact    Affected    Threat      Service      Lessons
                    Systems                 & Data
```

### On-Call Responsibilities

**Primary**: System Administrator
**Backup**: Security Lead
**Escalation**: CTO / Infrastructure Owner

---

## Compromised Pod Procedures

### Detection: Identifying Compromised Pods

#### Symptoms of Compromise
- Unexpected network traffic (data exfiltration)
- Unknown processes running
- CPU/memory spikes (crypto mining)
- Failed login attempts in logs
- Security alerts from monitoring

#### Diagnostic Commands

```bash
# 1. Check for anomalous resource usage
kubectl top pods --all-namespaces | awk '$3 > 90 || $4 > 90 {print $0}'

# 2. Check pod logs for suspicious activity
kubectl logs -n <namespace> <pod> --previous | grep -E "curl|wget|nc|ssh|python.*eval"

# 3. Check for unexpected network connections
kubectl exec -n <namespace> <pod> -- netstat -tulpn 2>/dev/null || \
kubectl exec -n <namespace> <pod> -- ss -tulpn

# 4. List running processes
kubectl exec -n <namespace> <pod> -- ps aux

# 5. Check for modified files (basic integrity check)
kubectl exec -n <namespace> <pod> -- find / -type f -mtime -1 -ls 2>/dev/null | head -20
```

### Containment: Immediate Isolation

#### Step 1: Isolate Compromised Pod
```bash
# Delete the pod immediately (forces recreation from clean image)
kubectl delete pod -n <namespace> <pod> --force --grace-period=0

# OR scale to zero if deployment
kubectl scale deployment -n <namespace> <deployment> --replicas=0
```

#### Step 2: Apply Network Quarantine
```bash
# Create deny-all egress policy for compromised namespace
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine-egress-deny
  namespace: <compromised-namespace>
spec:
  podSelector: {}
  policyTypes:
  - Egress
EOF
```

#### Step 3: Revoke Service Account Tokens
```bash
# Delete service account tokens
kubectl delete secrets -n <namespace> $(kubectl get secrets -n <namespace} -o jsonpath='{.items[?(@.type=="kubernetes.io/service-account-token")].metadata.name}')
```

### Eradication: Remove Threat

#### Step 1: Scan for Persistence Mechanisms
```bash
# Check for cron jobs
kubectl get cronjobs -n <namespace>

# Check for init containers that might be malicious
kubectl get pod -n <namespace> <pod> -o jsonpath='{.spec.initContainers[*].name}'

# Check for mounted volumes that might contain malicious code
kubectl get pod -n <namespace> <pod> -o jsonpath='{.spec.volumes[*].name}'
```

#### Step 2: Clean Up Resources
```bash
# Delete all pods in namespace
kubectl delete pods --all -n <namespace> --force --grace-period=0

# Delete suspicious deployments
kubectl delete deployment -n <namespace> <suspicious-deployment>

# Clean up persistent volumes (CAUTION: data loss)
kubectl delete pvc -n <namespace> --all
```

### Recovery: Restore Service

#### Step 1: Deploy Clean Version
```bash
# Redeploy from known-good configuration
kubectl rollout restart deployment -n <namespace> <deployment>

# Verify new pods are running
kubectl rollout status deployment -n <namespace> <deployment>
```

#### Step 2: Remove Network Quarantine
```bash
kubectl delete networkpolicy quarantine-egress-deny -n <namespace>
```

#### Step 3: Monitor for Recurrence
```bash
# Watch for suspicious behavior in new pods
watch -n 5 "kubectl top pods -n <namespace> | tail -10"
```

---

## Network Policy Incidents

### Scenario: Pod Cannot Access Required Service

#### Diagnostic Steps

```bash
# 1. Verify pod has network policy allowing required traffic
kubectl get networkpolicies -n <namespace> -o yaml

# 2. Check if destination has ingress policy allowing traffic
kubectl get networkpolicies -n <destination-namespace> -o yaml

# 3. Test connectivity from pod
kubectl exec -n <namespace> <pod> -- nc -zv <destination-service> <port>

# 4. Check for default-deny blocking traffic
kubectl get networkpolicy -n <namespace> default-deny-ingress -o yaml
```

#### Resolution Procedure

```bash
# Step 1: Create temporary allow-all policy (emergency only)
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: emergency-allow-all
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector: {}
  egress:
  - to:
    - namespaceSelector: {}
EOF

# Step 2: Test connectivity
kubectl exec -n <namespace> <pod> -- curl -I http://<destination-service>:<port>

# Step 3: Create proper allow policy (replace temporary)
# (See kubernetes-manifests/security/network/ for examples)

# Step 4: Remove emergency policy
kubectl delete networkpolicy emergency-allow-all -n <namespace>
```

### Scenario: Unexpected Connectivity Blocked

#### Common Causes
1. **Pod Label Mismatch**: Policy selector doesn't match pod labels
2. **Port Mismatch**: Policy allows different port than service uses
3. **Namespace Mismatch**: Policy allows wrong namespace
4. **DNS Blocked**: DNS policy missing or too restrictive

#### Diagnostic Commands

```bash
# Check pod labels
kubectl get pod -n <namespace> <pod> -o jsonpath='{.metadata.labels}' | jq .

# Check service ports
kubectl get svc -n <namespace> <service> -o jsonpath='{.spec.ports}' | jq .

# Check DNS policy
kubectl get networkpolicy -n <namespace> -o yaml | grep -A 10 "allow-dns"
```

---

## RBAC & Authorization Issues

### Scenario: Service Account Cannot Access Resource

#### Diagnostic Steps

```bash
# 1. Check service account permissions
kubectl auth can-i list pods --as=system:serviceaccount:<namespace>:<service-account> -n <namespace>

# 2. Check role bindings
kubectl get rolebindings,clusterrolebindings -A | grep <service-account>

# 3. Review role/clusterrole permissions
kubectl get role,clusterrole -o yaml | grep -A 20 "name: <role-name>"

# 4. Check audit logs for authorization denials
kubectl get events -n <namespace> --field-selector reason=Forbidden
```

#### Resolution Procedure

```bash
# Step 1: Create temporary admin role (emergency only)
kubectl create rolebinding emergency-admin \
  --clusterrole=admin \
  --serviceaccount=<namespace>:<service-account> \
  --namespace=<namespace>

# Step 2: Test access
kubectl auth can-i list pods --as=system:serviceaccount:<namespace>:<service-account> -n <namespace>

# Step 3: Create proper role with minimum permissions
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: <service-account>-role
  namespace: <namespace>
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
EOF

# Step 4: Create role binding
kubectl create rolebinding <service-account>-binding \
  --role=<service-account>-role \
  --serviceaccount=<namespace>:<service-account> \
  --namespace=<namespace>

# Step 5: Remove temporary admin role
kubectl delete rolebinding emergency-admin -n <namespace>
```

### Scenario: Unauthorized Access Attempt Detected

#### Response Procedure

```bash
# Step 1: Identify source of unauthorized access
kubectl get events -A --field-selector reason=Forbidden | tail -20

# Step 2: Check audit logs
kubectl logs -n kube-system kube-apiserver-zephyr --tail=100 | grep -i "denied\|forbidden"

# Step 3: Revoke suspicious service account tokens
kubectl delete secrets -A -l kubernetes.io/service-account-name=<suspicious-account>

# Step 4: Disable service account
kubectl patch serviceaccount <suspicious-account> -n <namespace> -p '{"automountServiceAccountToken": false}'

# Step 5: Investigate and document (see Post-Incident Analysis)
```

---

## Security Audit Procedures

### Monthly Audit Checklist

#### Network Policies
- [ ] Review all namespaces have network policies
- [ ] Verify no allow-all policies exist (except emergency)
- [ ] Test critical service connectivity
- [ ] Document any policy exceptions with justification
- [ ] Check for unused policies (delete if safe)

#### Pod Security
- [ ] Verify Pod Security labels on all namespaces
- [ ] Check for pods violating security baseline
- [ ] Review privileged pods (minimize use)
- [ ] Audit hostPath volume usage (minimize)
- [ ] Check for containers running as root

#### RBAC
- [ ] Audit all ClusterRoles/ClusterRoleBindings
- [ ] Remove unused service accounts
- [ ] Review admin privileges (minimize)
- [ ] Check for wildcard permissions (*)
- [ ] Verify role bindings follow least privilege

#### Resource Management
- [ ] Review LimitRanges (ensure all namespaces have defaults)
- [ ] Check ResourceQuotas (prevent resource exhaustion)
- [ ] Verify HPA configurations (prevent oscillation)
- [ ] Audit resource requests/limits (right-size)

#### Monitoring & Logging
- [ ] Verify Prometheus scraping all pods
- [ ] Check log aggregation working
- [ ] Test alert delivery (email, Slack, etc.)
- [ ] Review security alerts (false positives?)
- [ ] Audit retention policies (logs, metrics)

### Quarterly Deep Audit

```bash
# 1. Generate comprehensive security report
./scripts/security-audit.sh > quarterly-audit-$(date +%Y%m%d).txt

# 2. Review all CVEs in running images
trivy image k8s.gcr.io/kube-apiserver:v1.35.2

# 3. Scan for exposed credentials
kubectl get secrets --all-namespaces -o json | jq -r '.items[] | select(.data.token) | .metadata.name'

# 4. Review network topology changes
kubectl get networkpolicies --all-namespaces -o yaml > network-policies-backup.yaml

# 5. Generate compliance report
./scripts/compliance-check.sh > compliance-report-$(date +%Y%m%d).txt
```

---

## Rollback Procedures

### Rollback Network Policies

```bash
# Scenario: Network policy breaking critical service

# 1. Identify problematic policy
kubectl get networkpolicy -n <namespace> --sort-by=.metadata.creationTimestamp

# 2. Save policy for analysis
kubectl get networkpolicy -n <namespace> <policy-name> -o yaml > /tmp/<policy-name>-backup.yaml

# 3. Delete problematic policy
kubectl delete networkpolicy -n <namespace> <policy-name>

# 4. Verify service recovery
kubectl get pods -n <namespace> -w

# 5. Document incident
echo "$(date): Rolled back networkpolicy <policy-name> in <namespace>" >> /var/log/k8s-security-rollback.log
```

### Rollback Pod Security Admission

```bash
# Scenario: Pod Security policy blocking legitimate deployment

# 1. Identify violating namespace
kubectl get namespaces -L pod-security.kubernetes.io/enforce-violations

# 2. Temporarily relax enforcement
kubectl label ns <namespace> pod-security.kubernetes.io/enforce=privileged --overwrite

# 3. Redeploy application
kubectl rollout restart deployment -n <namespace> <deployment>

# 4. Investigate and fix policy violations
kubectl get pod -n <namespace> <pod> -o yaml | grep -A 20 "violations"

# 5. Re-enforce correct level after fix
kubectl label ns <namespace> pod-security.kubernetes.io/enforce=baseline --overwrite
```

### Rollback RBAC Changes

```bash
# Scenario: RBAC change breaking access

# 1. Identify recent RBAC changes
kubectl get rolebindings,clusterrolebindings --sort-by=.metadata.creationTimestamp

# 2. Save current state
kubectl get rolebinding,clusterrolebinding -A -o yaml > /tmp/rbac-backup-$(date +%Y%m%d-%H%M).yaml

# 3. Restore from backup
kubectl apply -f /tmp/rbac-backup-previous-good.yaml

# 4. Verify access restored
kubectl auth can-i list pods --as=system:serviceaccount:<namespace>:<service-account> -n <namespace>
```

### Emergency Rollback: Remove All Security Policies

```bash
# CRITICAL: Only use in extreme emergencies

# 1. Remove all network policies
kubectl delete networkpolicy --all --all-namespaces

# 2. Remove all Pod Security labels
kubectl get namespaces --no-headers | xargs -I {} kubectl label ns {} pod-security.kubernetes.io/enforce-

# 3. Remove all LimitRanges
kubectl delete limitrange --all --all-namespaces

# 4. Restore basic operations
kubectl get pods --all-namespaces

# 5. Document emergency rollback
echo "$(date): EMERGENCY ROLLBACK - All security policies removed" >> /var/log/k8s-emergency.log
```

---

## Post-Incident Analysis

### Incident Report Template

```markdown
# Security Incident Report

**Incident ID**: SEC-YYYYMMDD-001
**Date**: YYYY-MM-DD
**Severity**: [Critical/High/Medium/Low]
**Status**: [Open/Resolved/Closed]

## Executive Summary
[Brief 2-3 sentence summary]

## Timeline
| Time | Event |
|------|-------|
| HH:MM | Incident detected |
| HH:MM | Containment initiated |
| HH:MM | Service restored |
| HH:MM | Post-incident review |

## Impact Assessment
- **Affected Systems**: [list]
- **Data Exposed**: [yes/no/details]
- **Service Disruption**: [duration]
- **Users Affected**: [count]

## Root Cause Analysis
[What happened and why]

## Immediate Actions Taken
[Containment, eradication, recovery steps]

## Preventive Measures
[Long-term fixes to prevent recurrence]

## Lessons Learned
[What went well, what could be improved]

## Follow-Up Actions
- [ ] [Action 1] - Owner: [Name] - Due: [Date]
- [ ] [Action 2] - Owner: [Name] - Due: [Date]
```

### Continuous Improvement

**Monthly Reviews**:
- Review all security incidents from past month
- Identify patterns and trends
- Update runbook with new procedures
- Schedule training on common issues

**Quarterly Reviews**:
- Comprehensive security assessment
- Update security policies based on new threats
- Red team exercises (simulated attacks)
- Update documentation and runbooks

**Annual Reviews**:
- Complete security framework overhaul
- Threat modeling for all services
- Compliance audit (if applicable)
- Major documentation updates

---

## Appendix: Quick Reference

### Critical Commands (Save These!)

```bash
# Delete all pods in namespace (emergency)
kubectl delete pods --all -n <namespace> --force --grace-period=0

# Block all egress from namespace (quarantine)
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
  - Egress
EOF

# Revoke all service account tokens in namespace
kubectl delete secrets -n <namespace> -l kubernetes.io/service-account-token=true

# Scale deployment to zero immediately
kubectl scale deployment -n <namespace> <deployment> --replicas=0

# Get all security events from last hour
kubectl get events -A --field-selector type=Warning --since=1h
```

### Emergency Contacts

| Role | Name | Contact |
|------|------|---------|
| Primary On-Call | [Name] | [Email/Phone] |
| Security Lead | [Name] | [Email/Phone] |
| Infrastructure Owner | [Name] | [Email/Phone] |
| CTO | [Name] | [Email/Phone] |

### External Resources

- **Kubernetes Security Docs**: https://kubernetes.io/docs/concepts/security/
- **CIS Kubernetes Benchmark**: https://www.cisecurity.org/benchmark/kubernetes
- **OWASP Kubernetes Top 10**: https://owasp.org/www-project-kubernetes-top-ten

---

**Runbook Version**: 1.0
**Last Updated**: 2026-03-21
**Next Review**: 2026-04-21
**Maintained By**: Cluster Operations Team
