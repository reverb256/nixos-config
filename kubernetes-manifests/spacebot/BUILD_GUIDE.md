# Spacebot Nix Container Build Guide

**Status:** 🟡 IN PROGRESS - Container module created, testing pending

## Overview

This guide explains how to build Spacebot as a reproducible NixOS container image using `dockerTools.buildLayeredImage`. This approach provides:

- ✅ **Reproducibility** - Same inputs always produce identical image hashes
- ✅ **NixOS-native workflow** - No Dockerfile or external build tools needed
- ✅ **Better integration** - Proper layer structure and container metadata
- ✅ **Easier updates** - Single Nix expression to rebuild everything

## Architecture

```
NixOS Module System
    ├── services.spacebot.nix          → Systemd/Podman (current, working)
    └── services.spacebot.default.nix  → Container module (K8s, optional)
            ↓
    dockerTools.buildLayeredImage
            ↓
    spacebot-nixos:latest (Nix store path)
            ↓
    Option 1: Load into Docker (docker load)
    Option 2: Seed to kubelet (seedDockerImages)
    Option 3: Push to registry (docker push)
            ↓
    Kubernetes Deployment
```

## Module Structure

### Existing Module (Systemd/Podman)
**Path:** `/etc/nixos/modules/services/spacebot.nix`

- **Status:** ✅ Working, currently in production
- **Deployment:** systemd service with Podman container
- **Configuration:** Comprehensive (Discord, Slack, Telegram, API keys)
- **Usage:** `services.spacebot.enable = true;`

### New Module (Container)
**Path:** `/etc/nixos/modules/services/spacebot/default.nix`

- **Status:** 🟡 Created, testing pending
- **Deployment:** Nix-built container image for Kubernetes
- **Configuration:** Minimal (container build only)
- **Usage:** `services.spacebot-container.enable = true;`

## Building the Container Image

### Step 1: Enable the Container Module

Add to your NixOS configuration (e.g., `hosts/zephyr/configuration.nix`):

```nix
{
  # Enable Spacebot container builder (optional, for K8s)
  services.spacebot-container.enable = true;

  # The existing systemd service can stay enabled
  services.spacebot.enable = true;
}
```

### Step 2: Build the Container Image

```bash
# From /etc/nixos directory
cd /etc/nixos

# Build just the container image (fastest)
nix-build . -A spacebot-container-image

# Or rebuild the system (will build the image as dependency)
just switch
```

**Output:** `/nix/store/XXXX-spacebot-container-image.tar.gz`

### Step 3: Load Image into Container Runtime

#### Option A: Using Docker (recommended for Kubernetes)

```bash
# Load the image into Docker
docker load < /nix/store/XXXX-spacebot-container-image

# Verify it's loaded
docker images | grep spacebot

# Tag it for local registry (optional)
docker tag spacebot:latest localhost:5000/spacebot:latest
```

#### Option B: Using Podman (direct Nix store access)

```bash
# Podman can use Nix store paths directly
# Just update the deployment image path:
image: /nix/store/XXXX-spacebot-container-image
```

#### Option C: Push to Registry

```bash
# For multi-cluster deployments
docker tag spacebot:latest ghcr.io/yourusername/spacebot:nixos-latest
docker push ghcr.io/yourusername/spacebot:nixos-latest
```

## Deploying to Kubernetes

### Option 1: Local Registry (simplest)

```bash
# Start local registry on Nexus (storage node)
kubectl apply -f kubernetes-manifests/local-registry/

# Load and push image
docker load < /nix/store/XXXX-spacebot-container-image
docker tag spacebot:latest localhost:5000/spacebot:latest
docker push localhost:5000/spacebot:latest

# Update deployment to use local registry
# image: localhost:5000/spacebot:latest
kubectl apply -f kubernetes-manifests/spacebot/deployment-fixed.yaml
```

### Option 2: Direct Nix Store (podman-only)

```bash
# Get the exact Nix store path
IMAGE_PATH=$(nix-build . -A spacebot-container-image)

# Update deployment with exact path
sed -i "s|image: .*|image: $IMAGE_PATH|" \
  kubernetes-manifests/spacebot/deployment-fixed.yaml

# Deploy
kubectl apply -f kubernetes-manifests/spacebot/deployment-fixed.yaml
```

### Option 3: External Registry (production)

```bash
# Build and push to GitHub Container Registry
docker load < /nix/store/XXXX-spacebot-container-image
docker tag spacebot:latest ghcr.io/reverb256/spacebot:nixos-latest
docker push ghcr.io/reverb256/spacebot:nixos-latest

# Update deployment
# image: ghcr.io/reverb256/spacebot:nixos-latest
kubectl apply -f kubernetes-manifests/spacebot/deployment-fixed.yaml
```

## Verifying the Deployment

```bash
# Check pod status
kubectl get pods -n spacebot

# View logs
kubectl logs -f deployment/spacebot -n spacebot

# Check health endpoint
kubectl port-forward -n spacebot deployment/spacebot 19898:19898
curl http://localhost:19898/api/health
```

## Troubleshooting

### Issue: Container exits with code 0

**Symptoms:** Pod starts, immediately exits with `Completed` status

**Possible Causes:**
1. Missing runtime dependencies
2. Incorrect entrypoint command
3. Missing configuration files
4. Failed health check

**Solutions:**
```bash
# Check what's in the container
docker run --rm --entrypoint sh /nix/store/XXXX-spacebot-container-image -c "ls -la /"

# Try running with shell access
docker run --rm -it --entrypoint sh /nix/store/XXXX-spacebot-container-image

# Check container logs
docker run --rm /nix/store/XXXX-spacebot-container-image
```

### Issue: Image pull errors

**Symptoms:** `ErrImageNeverPull` or `ImagePullBackOff`

**Solutions:**
```bash
# Verify image is loaded
docker images | grep spacebot

# Check image name matches deployment
kubectl describe pod -n spacebot -l app=spacebot

# For local registry, verify registry is running
kubectl get pods -n kube-system -l app=local-registry
```

### Issue: Permission denied on /data

**Symptoms:** Container can't write to data directory

**Solution:**
```bash
# Fix permissions on host
sudo chown -R 1000:1000 /var/lib/spacebot

# Or run as root in container (not recommended)
# Set securityContext.runAsUser: 0 in deployment
```

## Next Steps

1. **Test the container module** - Build and verify the image works
2. **Set up local registry** - Deploy local registry on Nexus for easier testing
3. **Update CI/CD** - Integrate container build into deployment pipeline
4. **Document secrets** - Use agenix for TELEGRAM_BOT_TOKEN and API keys
5. **Add monitoring** - Configure Prometheus scraping for Spacebot metrics

## Integration with Existing Systemd Service

The systemd Spacebot service can continue running during migration:

```bash
# Check current systemd service status
systemctl status spacebot

# After K8s deployment is verified, disable systemd
sudo systemctl disable --now spacebot

# Rollback if needed
sudo systemctl enable --now spacebot
```

## Resources

- **NixOS dockerTools docs:** https://nixos.org/manual/nixpkgs/stable/#sec-docker-tools
- **Kubernetes containers:** https://kubernetes.io/docs/concepts/containers/
- **Spacebot source:** https://github.com/spacedriveapp/spacebot

---

**Last Updated:** 2026-03-24
**Status:** Container module created, deployment testing pending
**Next Action:** Build container image and test deployment
