# Kubernetes Network Policies

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
