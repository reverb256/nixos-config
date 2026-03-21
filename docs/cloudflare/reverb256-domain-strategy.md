# reverb256.ca Domain Strategy with Cloudflare Tunnels

## Current Infrastructure

### Cloudflare Tunnel
- **Status**: Running (cloudflared pod in akash-services)
- **Purpose**: Securely expose services without public IP
- **How it works**: Cloudflare → Tunnel → Your Kubernetes Cluster

### Existing Subdomains
- `provider.reverb256.ca` → Akash Provider (port 8443)
- `*.ingress.provider.reverb256.ca` → Akash Tenant Ingress

## Recommended Subdomains for Services

### 🎮 Gaming & Entertainment
```
rtc.reverb256.ca         → WebRTC signaling (Jitsi/Nextcloud Talk)
game.reverb256.ca        → Game server (Minecraft, Valheim, etc)
stream.reverb256.ca      → Media server (Jellyfin, Plex)
```

### 💻 Development & Tools
```
git.reverb256.ca         → Gitea/Gitea (self-hosted Git)
ci.reverb256.ca          → Woodpecker/Drone CI
grafana.reverb256.ca     → Monitoring dashboards
k8s.reverb256.ca         → Kubernetes dashboard (with auth)
```

### 📁 File Storage & Sync
```
cloud.reverb256.ca       → Nextcloud (with TLS)
files.reverb256.ca       → FileRun (SFTP/WebDAV)
backup.reverb256.ca      → Restic/Borg backups
```

### 🤖 AI & Machine Learning
```
ai.reverb256.ca          → Ollama/LM Studio (local LLM API)
ml.reverb256.ca          → JupyterHub (notebooks)
training.reverb256.ca    → MLflow experiment tracking
```

### 🔧 Infrastructure & Admin
```
ha.reverb256.ca          → Home Assistant (smart home)
nps.reverb256.ca         → Nginx Proxy Manager
vault.reverb256.ca       → HashiCorp Vault
logs.reverb256.ca        → Loki log aggregation
```

## Implementation Strategy

### Step 1: Create Cloudflare Tunnel Routes
For each service, add a route in Cloudflare Tunnel:

```yaml
# Example: Add to cloudflared config
ingress:
  - hostname: git.reverb256.ca
    service: http://gitea.http.svc.cluster.local:3000
  - hostname: grafana.reverb256.ca
    service: http://grafana.http.svc.cluster.local:3000
```

### Step 2: Deploy Services to Kubernetes
Use your existing modules structure:

```nix
# Example: Gitea self-hosted Git
services.gitea = {
  enable = true;
  domain = "git.reverb256.ca";
  port = 3000;
};
```

### Step 3: Configure DNS (Automatic)
Cloudflare Tunnel automatically:
- Creates DNS records
- Issues TLS certificates (Let's Encrypt)
- Handles HTTPS termination
- Hides your home IP

### Step 4: Add Authentication (Recommended)
For sensitive services:

```nix
# OAuth2 Proxy for authentication
services.oauth2-proxy = {
  enable = true;
  provider = "cloudflare"; # Use Cloudflare Access
  protectedDomains = [
    "grafana.reverb256.ca"
    "git.reverb256.ca"
  ];
};
```

## Security Best Practices

### 1. Network Isolation
```yaml
# Put untrusted services in separate namespace
- git (public, readonly)
- ci (internal, authenticated)
- vault (highly restricted)
```

### 2. Rate Limiting
```yaml
# Cloudflare Firewall Rules
# - Limit login attempts
# - Block abuse patterns
# - Geo restrictions
```

### 3. Authentication
```yaml
# Options:
# - Cloudflare Access (SSO)
# - OAuth2 Proxy (GitHub/Google)
# - Basic auth (internal tools)
# - Client certificates (machine-to-machine)
```

## Quick Start Examples

### Example 1: Gitea (Self-Hosted Git)
```bash
# 1. Deploy Gitea
kubectl create namespace gitea
helm repo add gitea-charts https://dl.gitea.io/charts/
helm install gitea gitea-charts/gitea -n gitea

# 2. Add Cloudflare Tunnel route
# Login to Cloudflare Dashboard → Zero Trust → Networks
# Add route: git.reverb256.ca → http://gitea.gitea.svc.cluster.local:3000

# 3. Access
git clone https://git.reverb256.ca/username/repo.git
```

### Example 2: Grafana (Monitoring)
```bash
# 1. Deploy Grafana
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana -n monitoring

# 2. Add Cloudflare Tunnel route with auth
# Use Cloudflare Access to protect with email/password

# 3. Access
# Open: https://grafana.reverb256.ca
```

### Example 3: Nextcloud (File Storage)
```bash
# 1. Deploy Nextcloud
helm repo add nextcloud https://nextcloud.github.io/helm/
helm install nextcloud nextcloud/nextcloud -n storage

# 2. Configure storage
# Use PVC with Longhorn or local-path

# 3. Access
# Open: https://cloud.reverb256.ca
```

## Advantages of Cloudflare Tunnels

### ✅ Security
- **No open ports**: No need to expose 80/443 to internet
- **DDoS protection**: Cloudflare absorbs attacks
- **TLS termination**: Automatic HTTPS
- **IP hiding**: Your home IP stays private

### ✅ Performance
- **Global CDN**: Content cached worldwide
- **Smart routing**: Fastest path to users
- **Load balancing**: Automatic distribution

### ✅ Convenience
- **No port forwarding**: Bypass ISP restrictions
- **Dynamic DNS**: No need for dyndns services
- **Automatic HTTPS**: Zero config TLS
- **Free**: Generous free tier

## Resource Considerations

### Current Cluster Capacity
- **CPU**: 120 cores total (using ~20%)
- **Memory**: 512GB total (using ~15%)
- **Storage**: 8TB+ available
- **Network**: 1Gbps fiber

### Recommended Services to Add

**Priority 1 - High Value, Low Resource Usage**:
1. Grafana (monitoring dashboards)
2. Gitea (self-hosted Git)
3. Cloudflare Tunnel management UI

**Priority 2 - Medium Resource Usage**:
4. Nextcloud (file storage/sync)
5. Home Assistant (smart home automation)
6. JupyterHub (development notebooks)

**Priority 3 - Higher Resource Usage**:
7. Jellyfin (media streaming)
8. CI/CD (Woodpecker/Drone)
9. AI/ML services (Ollama, Jupyter)

## Migration Path

### Phase 1: Infrastructure (Week 1)
1. Set up OAuth2 Proxy for authentication
2. Create service namespaces (git, monitoring, storage)
3. Configure monitoring stack

### Phase 2: Core Services (Week 2-3)
1. Deploy Gitea (replace GitHub private repos)
2. Deploy Grafana (centralized monitoring)
3. Set up backup services

### Phase 3: Advanced Services (Week 4+)
1. Deploy Nextcloud (file sync)
2. Add CI/CD pipeline
3. Experiment with AI/ML services

## Cost/Benefit Analysis

### Monthly Costs (Cloud Tunnel Free Tier)
- Cloudflare Tunnel: $0 ✅
- TLS Certificates: $0 (Let's Encrypt) ✅
- DDoS Protection: $0 ✅
- CDN: Included ✅

### Resource Costs
- Additional services: Minimal (most are lightweight)
- Storage: Use existing 8TB+
- Bandwidth: Included with 1Gbps fiber

### Benefits
- **Privacy**: Data stays on your hardware
- **Control**: Full admin access
- **Performance**: Local network speed
- **Cost**: No subscription fees for most services
- **Learning**: Gain self-hosting experience

## Next Steps

1. **Choose 2-3 services** to start with
2. **I can help create NixOS modules** for each service
3. **Configure Cloudflare Tunnel routes** for each
4. **Set up authentication** using Cloudflare Access
5. **Deploy services** to your Kubernetes cluster

## Examples I Can Help Implement

- ✅ Gitea (self-hosted GitHub alternative)
- ✅ Grafana + Prometheus (monitoring)
- ✅ Nextcloud (file storage/sync)
- ✅ Home Assistant (smart home)
- ✅ Jenkins/Woodpecker (CI/CD)
- ✅ Jellyfin (media server)
- ✅ Nginx Proxy Manager (reverse proxy management)

Would you like me to help you set up any specific service? I can create the NixOS configuration and Kubernetes manifests for any of these!
