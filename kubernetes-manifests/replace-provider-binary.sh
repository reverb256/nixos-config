#!/usr/bin/env bash
# Quick script to replace provider binary during its brief startup window

set -e

NAMESPACE="akash-services"
FIXED_BINARY="/tmp/provider/provider-services-fixed"

echo "Waiting for provider container to start..."
echo "Will copy binary when container is running..."
echo ""

while true; do
    # Check if container is running
    if kubectl get pod -n $NAMESPACE akash-provider-0 -o jsonpath='{.status.containerStatuses[0].state.running}' | grep -q .; then
        echo "✓ Container is running! Copying fixed binary..."

        # Stream the binary using tar
        tar czf - -C /tmp/provider provider-services-fixed | \
        kubectl exec -i -n $NAMESPACE akash-provider-0 -- tar xzf - -C /tmp

        # Replace the binary
        kubectl exec -n $NAMESPACE akash-provider-0 -- sh -c "
            chmod +x /tmp/provider-services-fixed &&
            cp /usr/bin/provider-services /usr/bin/provider-services.backup &&
            cp /tmp/provider-services-fixed /usr/bin/provider-services &&
            echo '✓ Binary replaced successfully'
        "

        # Restart the pod to apply changes
        echo "Restarting pod to apply fixed binary..."
        kubectl delete pod -n $NAMESPACE akash-provider-0

        echo "✓ Done! Monitor startup with: kubectl logs -n $NAMESPACE akash-provider-0 -f"
        exit 0
    fi

    # Container not running, wait a bit
    sleep 2
done
