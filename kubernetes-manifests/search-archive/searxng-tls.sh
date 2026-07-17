#!/usr/bin/env bash
# Create TLS secret for SearXNG
kubectl create secret tls searxng-tls \
  --cert=kubernetes-manifests/search/searxng-tls.crt \
  --key=kubernetes-manifests/search/searxng-tls.key \
  -n search --dry-run=client -o yaml | kubectl apply -f -
