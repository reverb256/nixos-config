#!/bin/bash
# OpenCode Kubernetes wrapper
# Runs OpenCode inside a Kubernetes pod with autoscaling and resource limits

set -e

# Get the first available opencode pod
POD=$(kubectl get pods -n ai-coding -l app=opencode -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -z "$POD" ]]; then
    echo "❌ Error: No OpenCode pods found in ai-coding namespace"
    echo ""
    echo "Check pod status with:"
    echo "  kubectl get pods -n ai-coding"
    exit 1
fi

echo "🔷 Running OpenCode in Kubernetes pod"
echo "   Pod: $POD"
echo "   Version: 1.2.27 (container)"
echo ""

# Pass all arguments to opencode in the pod
kubectl exec -it -n ai-coding "$POD" -- /bin/opencode "$@"
