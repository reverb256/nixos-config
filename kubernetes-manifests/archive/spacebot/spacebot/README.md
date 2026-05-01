# Spacebot on Kubernetes

## Overview

Spacebot AI Agent deployed on Nexus node with persistent storage and AI Gateway integration.

## Architecture

- **Namespace**: `spacebot`
- **Node**: Nexus (10.1.1.120) - storage node
- **Storage**: 10Gi PVC (fast-local-ssd)
- **LLM Integration**: AI Gateway at `http://ai-inference-gateway.ai-inference.svc.cluster.local:8080`
- **Messaging**: Telegram (via agenix secrets)

## Deployment

### 1. Apply manifests

```bash
kubectl apply -f kubernetes-manifests/spacebot/
```

### 2. Update secrets with agenix

```bash
kubectl create secret generic spacebot-secrets \
  --from-literal=telegram-token=$(cat /run/agenix/spacebot-telegram-token) \
  --namespace=spacebot \
  --dry-run=client -o yaml \
  | kubectl apply -f -

# Optional: Add provider API keys if needed
kubectl create secret generic spacebot-secrets \
  --from-literal=zai-coding-plan-key=$(cat /run/agenix/zai-api-key) \
  --from-literal=kilo-api-key=$(cat /run/agenix/kilo-api-key) \
  --namespace=spacebot \
  --dry-run=client --merge=true -o yaml \
  | kubectl apply -f -
```

### 3. Verify deployment

```bash
# Check pod status
kubectl get pods -n spacebot

# Check logs
kubectl logs -f deployment/spacebot -n spacebot

# Check service
kubectl get svc -n spacebot

# Port-forward for local testing
kubectl port-forward -n spacebot deployment/spacebot 19898:19898
```

## Access

### Internal Cluster

- **Web UI**: http://spacebot.spacebot.svc.cluster.local:19898
- **API**: http://spacebot.spacebot.svc.cluster.local:19898/api/
- **Health**: http://spacebot.spacebot.svc.cluster.local:19898/api/health

### External (via Ingress)

Add to Caddy Ingress config:

```caddy
spacebot.cluster.local {
    reverse_proxy spacebot.spacebot.svc.cluster.local:19898
}
```

## Monitoring

Spacebot exposes Prometheus metrics at `/metrics` on port 19898.

ServiceMonitor configured for automatic scraping.

## Configuration

ConfigMap `spacebot-config` contains the main configuration. Edit with:

```bash
kubectl edit configmap spacebot-config -n spacebot
kubectl rollout restart deployment/spacebot -n spacebot
```

## Troubleshooting

### Pod stuck in ContainerCreating

```bash
kubectl describe pod -n spacebot
# Check PVC status
kubectl get pvc -n spacebot
# Check node capacity
kubectl describe node nexus | grep -A5 "Allocated resources"
```

### Rate limiting errors

Spacebot may encounter Z.AI rate limiting during profile generation. This is expected and handled with automatic retries.

### AI Gateway connectivity

```bash
# Test gateway connectivity from pod
kubectl exec -n spacebot deployment/spacebot -- \
  curl -s http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/api/health
```

## Migration from Podman (Zephyr)

### Disable old service

```bash
sudo systemctl stop spacebot
sudo systemctl disable spacebot
# Edit hosts/zephyr/configuration.nix to set services.spacebot.enable = false
```

### Data migration (optional)

```bash
# Copy data from Zephyr to Nexus
ssh zephyr "sudo tar -czf - /var/lib/spacebot" | \
  ssh nexus "sudo tar -xzf - -C /var/lib/"
```

## Resource Usage

- **CPU**: 500m - 2 cores (request - limit)
- **Memory**: 2Gi - 4Gi (request - limit)
- **Storage**: 10Gi (fast-local-ssd on Nexus)

## Dependencies

- AI Gateway deployment running in `ai-inference` namespace
- Agenix secrets deployed on Nexus host
- Storage class `fast-local-ssd` available on Nexus
