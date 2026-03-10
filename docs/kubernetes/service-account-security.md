# Service Account Token Security

## Policy: Explicit Token Mounting Only

Service account tokens are NOT auto-mounted to pods by default. This follows OWASP A01:2021 (Broken Access Control).

## Implementation

For each pod/deployment that needs a service account token:

```yaml
spec:
  template:
    spec:
      automountServiceAccountToken: false  # Default to false
      # Only enable if actually needed:
      # automountServiceAccountToken: true
```

## When to Enable

- Pod needs to communicate with Kubernetes API
- Pod uses controllers/operators
- Pod uses Kubernetes client libraries

## Testing

```yaml
# Test pod without token
apiVersion: v1
kind: Pod
metadata:
  name: test-no-token
spec:
  automountServiceAccountToken: false
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "ls /var/run/secrets/kubernetes.io/serviceaccount/ && exit 1 || exit 0"]
```

Apply with:
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-no-token
spec:
  automountServiceAccountToken: false
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "test ! -f /var/run/secrets/kubernetes.io/serviceaccount/token"]
EOF
```

## References

- https://kubernetes.io/docs/concepts/configuration/pod-configuration-service-account/
- https://owasp.org/Top10/A01_2021-Broken_Access_Control/
