#!/bin/bash
# Claude Code Kubernetes wrapper
# Runs Claude Code inside a Kubernetes pod with autoscaling and resource limits

set -e

# Get the first available claude-code pod
POD=$(kubectl get pods -n ai-coding -l app=claude-code -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -z "$POD" ]]; then
    echo "❌ Error: No Claude Code pods found in ai-coding namespace"
    echo ""
    echo "Check pod status with:"
    echo "  kubectl get pods -n ai-coding"
    exit 1
fi

echo "🔷 Running Claude Code in Kubernetes pod"
echo "   Pod: $POD"
echo "   Version: 2.1.77 (container)"
echo ""

# Pass all arguments to claude in the pod
kubectl exec -it -n ai-coding "$POD" -- /bin/claude "$@"
