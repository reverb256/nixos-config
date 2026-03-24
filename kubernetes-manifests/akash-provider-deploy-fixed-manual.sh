#!/bin/bash
# Akash Provider DNS SRV Fix - Manual Deployment Script
#
# This script deploys the fixed provider binary by modifying the StatefulSet
# to mount the binary from the host filesystem.

set -e

FIXED_BINARY="/tmp/provider/provider-services-fixed"
DEPLOYMENT_DIR="/etc/nixos/kubernetes-manifests"
NAMESPACE="akash-services"

echo "=== Akash Provider DNS SRV Fix Deployment ==="
echo ""

# Verify fixed binary exists
if [ ! -f "$FIXED_BINARY" ]; then
    echo "❌ ERROR: Fixed binary not found at $FIXED_BINARY"
    echo "Please build the binary first:"
    echo "  cd /tmp/provider"
    echo "  nix-shell build.nix --run 'go build -o provider-services-fixed ./cmd/provider-services'"
    exit 1
fi

echo "✓ Fixed binary found: $FIXED_BINARY"
echo "  Size: $(ls -lh $FIXED_BINARY | awk '{print $5}')"
echo ""

# Copy binary to accessible location on each node
echo "=== Copying binary to /var/tmp/provider-services on all nodes ==="
for host in zephyr nexus forge sentry; do
    echo "Copying to $host..."
    ssh $host "mkdir -p /var/tmp && cat > /var/tmp/provider-services-fixed" < $FIXED_BINARY
    ssh $host "chmod +x /var/tmp/provider-services-fixed"
done

echo "✓ Binary copied to all nodes"
echo ""

# Create a ConfigMap with the binary (for single-node alternative)
echo "=== Creating ConfigMap with provider binary ==="
# Note: ConfigMaps have size limits, so we'll use hostPath instead
echo "ConfigMap approach skipped - using hostPath volumeMount instead"
echo ""

# Scale down provider StatefulSet
echo "=== Scaling down provider StatefulSet ==="
kubectl scale statefulset akash-provider -n $NAMESPACE --replicas=0

echo "Waiting for pod to terminate..."
kubectl wait --for=delete pod/akash-provider-0 -n $NAMESPACE --timeout=60s

echo "✓ Provider pod terminated"
echo ""

# Patch StatefulSet to mount fixed binary
echo "=== Patching StatefulSet to mount fixed binary ==="
cat > /tmp/provider-patch.yaml <<'EOF'
spec:
  template:
    spec:
      containers:
      - name: provider
        volumeMounts:
        - name: provider-binary
          mountPath: /host-usr-bin
          readOnly: true
      volumes:
      - name: provider-binary
        hostPath:
          path: /var/tmp
          type: DirectoryOrCreate
      initContainers:
      - name: copy-provider-binary
        image: busybox:1.36
        command:
        - sh
        - -c
        - |
          #!/bin/sh
          set -e
          echo "Copying fixed provider binary..."
          cp /host-var-tmp/provider-services-fixed /usr/bin/provider-services
          chmod +x /usr/bin/provider-services
          echo "✓ Binary copied successfully"
        volumeMounts:
        - name: host-var-tmp
          mountPath: /host-var-tmp
        - name: host-usr-bin
          mountPath: /host-usr-bin
      volumes:
      - name: host-var-tmp
        hostPath:
          path: /var/tmp
          type: DirectoryOrCreate
EOF

kubectl patch statefulset akash-provider -n $NAMESPACE --patch-file=/tmp/provider-patch.yaml --type=merge

echo "✓ StatefulSet patched"
echo ""

# Scale up provider StatefulSet
echo "=== Scaling up provider StatefulSet ==="
kubectl scale statefulset akash-provider -n $NAMESPACE --replicas=1

echo "Waiting for pod to start..."
sleep 5

echo ""
echo "=== Monitoring provider startup ==="
echo "Watching logs for 30 seconds..."
timeout 30s kubectl logs -n $NAMESPACE akash-provider-0 -c provider -f &
LOGS_PID=$!

sleep 30
kill $LOGS_PID 2>/dev/null || true

echo ""
echo "=== Verifying provider status ==="
kubectl get pod -n $NAMESPACE akash-provider-0

echo ""
echo "=== Checking if DNS SRV fix is working ==="
if kubectl logs -n $NAMESPACE akash-provider-0 -c provider --tail=50 | grep -q "dns discovery success"; then
    echo "✓ DNS SRV discovery successful"
else
    echo "⚠️  DNS SRV discovery status unclear - check logs manually"
fi

echo ""
echo "=== Next Actions ==="
echo "1. Monitor provider: kubectl logs -n $NAMESPACE akash-provider-0 -f"
echo "2. Check health: kubectl exec -n $NAMESPACE akash-provider-0 -- curl -s http://localhost:8443/status"
echo "3. Verify leases: kubectl get leases -n $NAMESPACE"
echo ""
echo "If provider is working correctly:"
echo "- Clean up old binary: ssh <host> 'rm /var/tmp/provider-services-fixed'"
echo "- Remove hostPath volume mount from StatefulSet"
echo ""
echo "Documentation:"
echo "  - /etc/nixos/docs/kubernetes/akash-provider-fix-complete.md"
echo "  - /etc/nixos/docs/kubernetes/comprehensive-audit-2026-03-24.md"
