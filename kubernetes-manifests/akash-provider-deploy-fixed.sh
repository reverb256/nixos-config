#!/bin/bash
# Akash Provider DNS SRV Fix Deployment Script
#
# This script deploys the Akash provider with the DNS SRV malformed URL bug fix.
# The fix strips trailing dots from DNS SRV targets before constructing HTTP URLs.
#
# Date: 2026-03-23
# Status: Fix applied, ready for deployment

set -e

FIXED_BINARY="/tmp/provider/provider-services-fixed"
DOCKERFILE="/tmp/provider/Dockerfile.fixed"
IMAGE_NAME="akash-provider"
IMAGE_TAG="0.11.0-dnsfix"

echo "=== Akash Provider DNS SRV Fix Deployment ==="
echo ""

# Check if fixed binary exists
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

# Verify fix is in binary
if strings "$FIXED_BINARY" | grep -q "strings.TrimSuffix"; then
    echo "✓ Verified: DNS SRV fix is present in binary"
else
    echo "❌ ERROR: DNS SRV fix not found in binary"
    exit 1
fi

# Build Docker image
echo ""
echo "=== Building Docker Image ==="
cd /tmp/provider

if docker build -f "$DOCKERFILE" -t "${IMAGE_NAME}:${IMAGE_TAG}" . 2>&1; then
    echo "✓ Docker image built successfully: ${IMAGE_NAME}:${IMAGE_TAG}"
else
    echo "❌ ERROR: Docker build failed"
    echo ""
    echo "You may need to:"
    echo "  1. Add your user to the docker group: sudo usermod -aG docker \$USER"
    echo "  2. Log out and back in"
    echo "  3. Or run this script with sudo"
    exit 1
fi

# Tag image for registry (optional - modify as needed)
REGISTRY="${REGISTRY:-ghcr.io/your-username}"
FULL_IMAGE_TAG="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo "=== Deployment Instructions ==="
echo ""
echo "Option 1: Load into Kind cluster (for testing)"
echo "  kind load docker-image --name your-cluster-name ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "Option 2: Push to container registry"
echo "  docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE_TAG}"
echo "  docker push ${FULL_IMAGE_TAG}"
echo ""
echo "Option 3: Use local image (set imagePullPolicy: Never)"
echo "  kubectl patch statefulset akash-provider -n akash-services \\"
echo "    -p '{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"provider\",\"image\":\"${IMAGE_NAME}:${IMAGE_TAG}\",\"imagePullPolicy\":\"Never\"}]}}}}'"
echo ""

# Show current provider image
echo "=== Current Provider Deployment ==="
kubectl get statefulset akash-provider -n akash-services -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "Provider not currently deployed"

echo ""
echo "=== Fix Summary ==="
echo "Bug: Malformed URLs from DNS SRV records (trailing dots before port)"
echo "Fix: Strip trailing dot using strings.TrimSuffix()"
echo "File: cluster/util/service_discovery_agent.go (lines 9, 251-253)"
echo ""
echo "Documentation:"
echo "  - /etc/nixos/docs/kubernetes/akash-provider-dns-srv-fix-guide.md"
echo "  - /etc/nixos/docs/kubernetes/akash-provider-dns-srv-fix.patch"
echo "  - /etc/nixos/docs/kubernetes/akash-provider-root-cause-analysis-2026-03-23.md"
echo ""
