# Kubernetes Network Policies

> **Status:** Reference procedure
> **Last Verified:** 2026-08-09 (checked-in policy paths and command review)
> **Source:** `kubernetes/modules/`, `kubernetes-manifests/security/network/`, and the live Kubernetes API
>
> Verify the active policy objects and the CNI behavior before applying or testing a
> policy. The examples below are not a declaration of the current cluster policy set.

## Architecture: Default Deny with Explicit Allow

This implements a zero-trust network model where all pod-to-pod communication is denied by default.

## Applying Policies

```bash
# Apply in order
kubectl apply -f default-deny.yaml
kubectl apply -f dns-allow.yaml
kubectl apply -f ingress-allow.yaml
```

## Testing

```bash
# Apply policies
kubectl apply -f docs/kubernetes/network-policies/

# Test connectivity
kubectl run test-pod --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default

# Create two test pods to verify isolation
kubectl run pod-a --image=nginx --labels=app=test-a
kubectl run pod-b --image=busybox --labels=app=test-b --rm -it --restart=Never -- wget --timeout=2 pod-a -O-
# Should timeout (no connectivity)
```

## Per-Application Policies

Each application needs its own network policy. Use the templates as a starting point.
