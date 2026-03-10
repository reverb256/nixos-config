# Pod Security Admission Configuration

## Policy Level: Restricted

The cluster enforces the `restricted` Pod Security Standard by default.

## What This Prevents

- Privileged pods
- Host PID/IPC namespace sharing
- Arbitrary capabilities
- Root containers
- Host network access

## Exemptions

Currently no exemptions. Add exemptions via `exemptions` in PSA config if needed.

## Validation

```bash
# Test PSA is working
kubectl run test-pod --image=nginx --privileged=false
# Should succeed

kubectl run test-pod-privileged --image=nginx --privileged=true
# Should fail with "pod violates PodSecurity "restricted:latest"
```

## References

- https://kubernetes.io/docs/concepts/security/pod-security-admission/
- https://kubernetes.io/docs/concepts/security/pod-security-standards/
