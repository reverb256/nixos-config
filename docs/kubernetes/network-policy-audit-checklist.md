# Network Policy Audit Checklist
**Frequency**: Monthly
**Last Audit**: 2026-03-21
**Next Audit**: 2026-04-21
**Auditor**: Cluster Operations Team

---

## Audit Overview

This checklist provides a systematic approach to auditing Kubernetes network policies to ensure security best practices are maintained.

---

## Section 1: Policy Coverage Audit

### 1.1 Default-Deny Verification

**Objective**: Ensure all namespaces have default-deny ingress policy

**Procedure**:
```bash
# Check each namespace for default-deny policy
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== Namespace: $ns ==="
  kubectl get networkpolicy -n $ns -o json | jq -r '.items[] | select(.spec.policyTypes[] == "Ingress") | select(.spec.podSelector == {}) | .metadata.name'
  if [ $? -ne 0 ]; then
    echo "❌ MISSING: No default-deny policy found"
  else
    echo "✅ PASS: Default-deny policy exists"
  fi
done
```

**Pass Criteria**: All namespaces have default-deny ingress policy
**Exceptions**: `kube-system`, `kube-public`, `kube-flannel` (system namespaces)

### 1.2 DNS Policy Verification

**Objective**: Ensure all namespaces allow DNS resolution

**Procedure**:
```bash
# Check DNS policies
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== Namespace: $ns ==="
  kubectl get networkpolicy -n $ns -o yaml | grep -q "allow-dns"
  if [ $? -eq 0 ]; then
    echo "✅ PASS: DNS policy exists"
  else
    echo "❌ FAIL: No DNS policy found"
  fi
done
```

**Pass Criteria**: All namespaces with pods have DNS allow policy

### 1.3 Allow-All Policy Detection

**Objective**: Ensure no permissive allow-all policies exist

**Procedure**:
```bash
# Check for allow-all ingress/egress policies
kubectl get networkpolicy --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.ingress[]?.from[]?.namespaceSelector == {} or .spec.egress[]?.to[]?.namespaceSelector == {}) | "\(.metadata.namespace)/\(.metadata.name)"'
```

**Pass Criteria**: No allow-all policies (except emergency/temporary)
**Action if Found**: Document justification, add review date, plan removal

---

## Section 2: Policy Effectiveness Audit

### 2.1 Pod-to-Pod Communication Matrix

**Objective**: Verify all required communications are explicitly allowed

**Procedure**:

1. **Generate communication matrix**:
```bash
# Document all allowed inter-namespace communications
kubectl get networkpolicy --all-namespaces -o yaml > /tmp/network-policies.yaml

# Parse for allowed communications
grep -A 20 "from:" /tmp/network-policies.yaml | grep -E "namespace|podSelector" | \
  sed 's/^[ \t]*//' | sort | uniq
```

2. **Verify against documented requirements**:
   - Review `kubernetes-manifests/security/network/README.md`
   - Check each documented communication flow has policy
   - Identify undocumented communications

**Pass Criteria**: All documented communications have policies, no undocumented flows

### 2.2 Port Exposure Audit

**Objective**: Ensure only required ports are exposed

**Procedure**:
```bash
# List all allowed ports
kubectl get networkpolicy --all-namespaces -o json | \
  jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name): \([.spec.ingress[]?.ports[]?.port // .spec.egress[]?.ports[]?.port | tostring] | @tsv)"' | \
  grep -v "null"
```

**Audit Checklist**:
- [ ] Each exposed port documented in service manifest
- [ ] No wildcard port ranges (e.g., `port: 0-65535`)
- [ ] Sensitive ports (22, 3306, 5432, 6379) not exposed publicly
- [ ] Services using NodePort documented and justified

### 2.3 External Access Audit

**Objective**: Verify all external API access is necessary

**Procedure**:
```bash
# Find policies allowing external access (ipBlock: 0.0.0.0/0)
kubectl get networkpolicy --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.egress[]?.to[]?.ipBlock?.cidr == "0.0.0.0/0") | "\(.metadata.namespace)/\(.metadata.name)"'
```

**For each external access policy**:
- [ ] Service requires external API access
- [ ] Access restricted to specific ports (not all ports)
- [ ] Internal IP ranges excluded (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
- [ ] Documented in security policy documentation

---

## Section 3: Policy Configuration Audit

### 3.1 Label Selector Accuracy

**Objective**: Ensure policy pod selectors match actual pod labels

**Procedure**:
```bash
# Check for policies with non-matching selectors
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
  for policy in $(kubectl get networkpolicy -n $ns -o jsonpath='{.items[*].metadata.name}'); do
    selector=$(kubectl get networkpolicy -n $ns $policy -o jsonpath='{.spec.podSelector}')
    if [ -n "$selector" ]; then
      matching_pods=$(kubectl get pods -n $ns -l $selector --no-headers 2>/dev/null | wc -l)
      if [ "$matching_pods" -eq 0 ]; then
        echo "⚠️  WARNING: $ns/$policy selector matches 0 pods"
      fi
    fi
  done
done
```

**Pass Criteria**: All policy selectors match at least one pod (or are intentionally empty)

### 3.2 Policy Specificity Audit

**Objective**: Ensure policies are specific enough to be effective

**Review**:
```bash
# Find overly broad policies
kubectl get networkpolicy --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.podSelector == {} and (.spec.ingress[]?.from[]?.namespaceSelector == {} or .spec.egress[]?.to[]?.namespaceSelector == {})) | "\(.metadata.namespace)/\(.metadata.name)"'
```

**Audit Checklist**:
- [ ] Policies using namespaceSelector documented
- [ ] Empty podSelector justified (namespace-wide policy)
- [ ] No overly broad wildcard policies

### 3.3 Policy Version Control

**Objective**: Ensure all policies are in Git

**Procedure**:
```bash
# List all policies in cluster
kubectl get networkpolicy --all-namespaces -o jsonpath='{.items[*].metadata.namespace}/{.items[*].metadata.name}' | \
  sort > /tmp/cluster-policies.txt

# List all policies in Git
find /etc/nixos/kubernetes-manifests/security/network/ -name "*.yaml" -exec basename {} .yaml \; | \
  sort > /tmp/git-policies.txt

# Compare
diff /tmp/cluster-policies.txt /tmp/git-policies.txt
```

**Pass Criteria**: All cluster policies tracked in Git
**Action if Not**: Add missing policies to Git, document any intentionally untracked policies

---

## Section 4: Testing & Verification

### 4.1 Connectivity Testing

**Objective**: Verify all critical service communication works

**Test Cases**:
```bash
# Test 1: Searxng accessibility
kubectl port-forward -n search svc/searxng 7777:7777 &
PF_PID=$!
sleep 2
curl -s -o /dev/null -w "%{http_code}" http://localhost:7777/ | grep -q "200" && echo "✅ Searxng accessible" || echo "❌ Searxng not accessible"
kill $PF_PID

# Test 2: Akash provider connectivity
kubectl logs -n akash-services akash-provider-0 --tail=20 | grep -q "ERROR" && echo "❌ Provider errors" || echo "✅ Provider healthy"

# Test 3: Monitoring scraping
kubectl get --raw /api/v1/namespaces/monitoring/pods | grep -q "prometheus" && echo "✅ Prometheus accessible" || echo "❌ Prometheus not accessible"
```

**Pass Criteria**: All critical services accessible and functional

### 4.2 Policy Violation Detection

**Objective**: Ensure no unexpected policy violations

**Procedure**:
```bash
# Check for connectivity errors in pod logs
kubectl logs --all-containers=true --all-namespaces --tail=50 | \
  grep -E "connection refused|timeout|no route to host" | \
  grep -v "Readiness probe failed" | \
  wc -l
```

**Pass Criteria**: No unexpected connectivity errors
**Action if Found**: Investigate and update policies as needed

---

## Section 5: Documentation & Compliance

### 5.1 Exception Documentation

**Objective**: Ensure all policy exceptions are documented

**Procedure**:
1. Review `kubernetes-manifests/security/network/README.md`
2. Check each external access policy has justification
3. Verify all inter-namespace communications documented

**Documentation Checklist**:
- [ ] All allow-all policies documented with justification
- [ ] All external API access documented with business need
- [ ] All NodePort services documented and justified
- [ ] All policy exceptions have review dates

### 5.2 Runbook Accuracy

**Objective**: Verify security runbook is up-to-date

**Procedure**:
```bash
# Check runbook exists and is recent
if [ -f /etc/nixos/docs/kubernetes/security-runbook.md ]; then
  file_age=$(( ($(date +%s) - $(stat -c %Y /etc/nixos/docs/kubernetes/security-runbook.md)) / 86400 ))
  if [ $file_age -lt 90 ]; then
    echo "✅ Runbook updated within 90 days"
  else
    echo "⚠️  WARNING: Runbook is $file_age days old"
  fi
else
  echo "❌ ERROR: Runbook not found"
fi
```

**Review Checklist**:
- [ ] Rollback procedures tested and working
- [ ] Emergency contacts up-to-date
- [ ] Diagnostic commands tested and accurate
- [ ] Incident response procedures reflect current cluster state

---

## Section 6: Action Items & Remediation

### 6.1 Critical Issues (Fix Immediately)

**Template**:
```markdown
### Issue #[Number]: [Title]
- **Severity**: Critical/High/Medium/Low
- **Finding**: [What was found]
- **Risk**: [Why it matters]
- **Remediation**: [How to fix]
- **Owner**: [Who will fix]
- **Due Date**: [When to fix]
- **Status**: Open/In Progress/Resolved
```

### 6.2 Recommendations

**Template**:
```markdown
### Recommendation #[Number]: [Title]
- **Priority**: High/Medium/Low
- **Description**: [What to improve]
- **Benefit**: [Why it matters]
- **Effort**: [Time estimate]
- **Owner**: [Who will implement]
```

---

## Section 7: Audit Sign-Off

### 7.1 Audit Summary

**Audit Date**: [Date]
**Auditor**: [Name]
**Audit Duration**: [Time spent]
**Policies Reviewed**: [Count]
**Namespaces Reviewed**: [Count]

**Findings Summary**:
- Critical Issues: [Count]
- High Issues: [Count]
- Medium Issues: [Count]
- Low Issues: [Count]

**Overall Assessment**: [Pass/Fail/Needs Improvement]

### 7.2 Approval

| Role | Name | Signature | Date |
|------|------|----------|------|
| Auditor | | | |
| Security Lead | | | |
| Infrastructure Owner | | | |

---

## Appendix: Audit Scripts

### Automated Audit Script

```bash
#!/bin/bash
# network-policy-audit.sh
# Run this script to perform automated network policy audit

echo "=== Kubernetes Network Policy Audit ==="
echo "Date: $(date)"
echo ""

# Section 1: Coverage
echo "### 1. Policy Coverage ###"
echo "Default-deny policies:"
kubectl get networkpolicy --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.policyTypes[] == "Ingress") | select(.spec.podSelector == {}) | "\(.metadata.namespace): \(.metadata.name)"' | \
  sort | uniq -c

echo ""
echo "DNS policies:"
kubectl get networkpolicy --all-namespaces -o json | \
  jq -r '.items[] | select(.metadata.name | contains("dns")) | "\(.metadata.namespace): \(.metadata.name)"' | \
  sort | uniq -c

# Section 2: Allow-All Detection
echo ""
echo "### 2. Allow-All Policies ###"
kubectl get networkpolicy --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.ingress[]?.from[]?.namespaceSelector == {} or .spec.egress[]?.to[]?.namespaceSelector == {}) | "\(.metadata.namespace)/\(.metadata.name)"'

# Section 3: External Access
echo ""
echo "### 3. External Access Policies ###"
kubectl get networkpolicy --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.egress[]?.to[]?.ipBlock?.cidr == "0.0.0.0/0") | "\(.metadata.namespace)/\(.metadata.name)"'

# Section 4: Policy Counts
echo ""
echo "### 4. Policy Counts per Namespace ###"
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
  count=$(kubectl get networkpolicy -n $s --no-headers 2>/dev/null | wc -l)
  echo "$ns: $count policies"
done | sort -t: -k2 -rn

echo ""
echo "=== Audit Complete ==="
```

### Manual Audit Worksheet

Print this section for manual audit:

```
NETWORK POLICY AUDIT WORKSHEET
Date: ___________  Auditor: ___________

[ ] 1. Default-deny policies present in all namespaces
[ ] 2. DNS policies present in all namespaces
[ ] 3. No allow-all policies (or documented exceptions)
[ ] 4. All required communications documented
[ ] 5. All exposed ports documented and justified
[ ] 6. External access minimized and documented
[ ] 7. Policy selectors match actual pods
[ ] 8. Policies tracked in Git
[ ] 9. Critical services accessible
[ ] 10. No unexpected connectivity errors

Notes:
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________

Issues Found:
1. ______________________________________________________________
2. ______________________________________________________________
3. ______________________________________________________________

Recommendations:
1. ______________________________________________________________
2. ______________________________________________________________
3. ______________________________________________________________
```

---

**Audit Checklist Version**: 1.0
**Last Updated**: 2026-03-21
**Next Audit**: 2026-04-21
**Maintained By**: Cluster Operations Team
