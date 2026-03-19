# SearXNG Kubernetes Migration

## Overview
Migrates SearXNG privacy-respecting metasearch engine from systemd to Kubernetes.

## Why Migrate?
- **Separation of Concerns**: NixOS rebuilds don't affect search availability
- **Scalability**: Can scale horizontally if needed
- **Consistency**: Same deployment pattern as other services (GlitchTip, n8n, HA)

## Components
- **Deployment**: Single replica (stateless)
- **Service**: ClusterIP on port 7777
- **ConfigMap**: settings.yml with engine configuration
- **Secret**: SEARXNG_SECRET_KEY for result validation

## Integration Points
- **AI Inference Gateway**: Uses SearXNG at `http://searxng.search.svc.cluster.local:7777`
- **Web Search**: Provides metasearch for AI knowledge base
- **Code Search**: Searches `/etc/nixos` and `/home/j_kro`

## Migration Steps

### 1. Deploy to Kubernetes
```bash
kubectl apply -f /etc/nixos/kubernetes-manifests/searxng/
```

### 2. Verify Deployment
```bash
kubectl get pods -n search
kubectl logs -n search deployment/searxng
```

### 3. Test Service
```bash
# Port-forward for testing
kubectl port-forward -n search deployment/searxng 7777:7777

# Test search
curl "http://localhost:7777/search?q=test&format=json"
```

### 4. Update AI Inference Gateway
The AI Inference Gateway will need to be updated to use the new Kubernetes service URL:
```
Old: http://127.0.0.1:7777
New: http://searxng.search.svc.cluster.local:7777
```

### 5. Disable Systemd Service (After Verification)
```bash
# Update NixOS configuration
# In /etc/nixos/hosts/zephyr/configuration.nix, set:
services.searxng.enable = false;

# Rebuild NixOS
sudo nixos-rebuild switch

# Stop service
sudo systemctl stop searx
```

## Service Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/search` | HTML search results |
| `/search?format=json` | JSON API for AI Gateway |
| `/config` | Configuration interface |

## Resource Requirements
- **Memory**: 128Mi request, 512Mi limit
- **CPU**: 100m request, 500m limit
- **Storage**: None (stateless)

## Troubleshooting

### Search engines returning errors
- Check logs: `kubectl logs -n search deployment/searxng`
- Some engines may rate-limit or block automated requests
- Consider increasing `request_timeout` in settings.yml

### AI Gateway can't connect
- Verify service: `kubectl get svc -n search searxng`
- Check DNS from AI Gateway pod
- Ensure search namespace is accessible from ai-inference namespace
