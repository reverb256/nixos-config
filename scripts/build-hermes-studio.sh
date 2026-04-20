#!/usr/bin/env bash
# Build Hermes Studio container image from source using Docker
# Run on nexus where K3s + local registry are available
#
# Usage: sudo bash build-hermes-studio.sh

set -euo pipefail

REPO="https://github.com/JPeetz/Hermes-Studio"
VERSION="1.18.1"
REV="4788d9cebf0cf1c4564e6da4ee65752a9d746517"
IMAGE_NAME="localhost:5000/hermes-studio:${VERSION}"
BUILD_DIR="/tmp/hermes-studio-build"

echo "=== Building Hermes Studio ${VERSION} ==="

# Clone or update the repo
if [ -d "${BUILD_DIR}/.git" ]; then
  echo "Updating existing clone..."
  cd "${BUILD_DIR}"
  git fetch origin main
  git checkout "${REV}"
else
  echo "Cloning repo..."
  git clone "${REPO}" "${BUILD_DIR}"
  cd "${BUILD_DIR}"
  git checkout "${REV}"
fi

echo "Building Docker image..."
docker build -t "hermes-studio:${VERSION}" .

echo "Tagging for local registry..."
docker tag "hermes-studio:${VERSION}" "${IMAGE_NAME}"

echo "Pushing to local K3s registry..."
docker push "${IMAGE_NAME}"

echo ""
echo "=== Build complete ==="
echo "Image: ${IMAGE_NAME}"
echo ""
echo "Deploy with:"
echo "  kubectl apply -f /etc/nixos/kubernetes-manifests/ai-inference/hermes-studio.yaml"
