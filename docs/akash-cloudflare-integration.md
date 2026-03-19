# Akash Cloudflare Integration - Usage Guide

## Overview

This module provides 6 production-ready Cloudflare integration features for Akash Network providers:

1. **Automated Tenant DNS Setup** (⭐⭐⭐ High Priority)
   - Automatically creates DNS records for tenant deployments
   - Pattern: `tenant-name.dedicated.ingress.reverb256.ca`

2. **Smart Cache Invalidation** (⭐⭐ High Priority)
   - Purges Cloudflare cache when tenants deploy
   - Targeted purges (not full zone) for better performance

3. **Prometheus Integration** (⭐⭐ High Priority)
   - Exports Cloudflare metrics to Prometheus
   - 6 metrics: requests, bandwidth, cache hit rate, threats, errors, DNS records

4. **Health Monitoring Dashboard** (⭐⭐ Nice to Have)
   - Real-time provider health status
   - Auto-updating HTML dashboard

5. **DNS Cleanup Automation** (⭐ Medium Priority)
   - Removes stale DNS records daily
   - 24-hour grace period before deletion

6. **Status Page** (⭐ Optional)
   - Public-facing provider status page
   - Shows provider info, GPU models, pricing

## Quick Start

### 1. Generate Cloudflare API Token

```bash
# 1. Go to: https://dash.cloudflare.com/profile/api-tokens
# 2. Click "Create Token"
# 3. Use template "Edit zone DNS" or custom permissions
# 4. Set permissions:
#    - Zone - DNS - Edit
#    - Zone - Zone - Read
#    - Zone - Cache Purge - Purge
# 5. Set zone resources to "Include" > "Specific zone" > reverb256.ca
# 6. Set TTL to "Never expire"
# 7. Copy token and encrypt with agenix:

agenix -e secrets/cloudflare-api-token.age

# 8. Paste token into the editor and save
```

### 2. Enable Module on Zephyr

Add to `/etc/nixos/hosts/zephyr/configuration.nix`:

```nix
services.akash-cloudflare-integration = {
  enable = true;

  # Global configuration
  domain = "reverb256.ca";
  zoneId = "abc123def456"; # Get from Cloudflare dashboard
  tokenFile = "/run/agenix/cloudflare-api-token";

  # Provider endpoints
  providerEndpoint = "http://10.1.1.120:30843";
  providerGrpcEndpoint = "10.1.1.120:30844";
  ingressDomain = "ingress.reverb256.ca";

  # Feature 1: Automated Tenant DNS Setup
  dnsWatcher.enable = true;

  # Feature 2: Smart Cache Invalidation
  cachePurge.enable = true;

  # Feature 3: Prometheus Integration
  metricsExporter.enable = true;

  # Feature 4: Health Monitoring Dashboard
  healthDashboard.enable = true;

  # Feature 5: DNS Cleanup Automation
  dnsCleanup.enable = true;

  # Feature 6: Status Page (optional)
  statusPage.enable = true;
};

# Add agenix secret
age.secrets.cloudflare-api-token = {
  file = "${inputs.self}/secrets/cloudflare-api-token.age";
  mode = "440";
  owner = "root";
  group = "root";
};
```

### 3. Deploy

```bash
# Validate configuration
nix flake check

# Apply to Zephyr
just switch

# Deploy to cluster
just deploy
```

## Feature Configuration

### Feature 1: Automated Tenant DNS Setup

**Service:** `aksh-cloudflare-dns-watcher.service`

**What it does:**
- Watches Kubernetes for new Akash deployments
- Extracts tenant name from deployment labels
- Creates DNS record: `tenant-name.dedicated.ingress.reverb256.ca`
- Points to provider ingress IP

**Configuration:**
```nix
dnsWatcher = {
  enable = true;
  pollInterval = 30;  # Check every 30 seconds
  dnsRecordPrefix = "dedicated";  # *.dedicated.ingress.reverb256.ca
};
```

**Testing:**
```bash
# Deploy test Akash workload
kubectl apply -f test-deployment.yaml

# Verify DNS record created
dig myapp.dedicated.ingress.reverb256.ca

# Check logs
journalctl -u akash-cloudflare-dns-watcher -f
```

### Feature 2: Smart Cache Invalidation

**Service:** `aksh-cloudflare-cache-purge@<tenant>.service`

**What it does:**
- Triggered automatically after DNS record creation
- Purges Cloudflare cache for tenant's URLs only
- Targeted purge using `files` parameter (not full zone)

**Configuration:**
```nix
cachePurge = {
  enable = true;
  purgeDelay = 5;  # Wait 5 seconds after DNS creation
};
```

**Testing:**
```bash
# Deploy workload with static assets
# Access URL to populate cache
curl https://myapp.dedicated.ingress.reverb256.ca/

# Trigger manual purge
systemctl start akash-cloudflare-cache-purge@myapp

# Verify cache purged in Cloudflare dashboard
```

### Feature 3: Prometheus Integration

**Service:** `akash-cloudflare-metrics.service` (timer: every 5 minutes)

**What it does:**
- Fetches analytics from Cloudflare API
- Writes metrics to `/var/lib/prometheus/node-exporter/textfile-collector/cloudflare.prom`
- Node-exporter automatically scrapes this directory

**Metrics:**
- `cloudflare_requests_total` - Total requests
- `cloudflare_bandwidth_bytes_total` - Total bandwidth
- `cloudflare_cache_hit_rate` - Cache hit percentage
- `cloudflare_threats_total` - Threats blocked
- `cloudflare_http_errors_total` - HTTP 4xx/5xx errors
- `cloudflare_dns_records_total` - Total DNS records

**Configuration:**
```nix
metricsExporter = {
  enable = true;
  scrapeInterval = 300;  # 5 minutes
  metricsDir = "/var/lib/prometheus/node-exporter/textfile-collector";
};
```

**Testing:**
```bash
# Wait 5 minutes for first scrape
cat /var/lib/prometheus/node-exporter/textfile-collector/cloudflare.prom

# Query Prometheus
curl 'http://sentry:9090/api/v1/query?query=cloudflare_cache_hit_rate'

# Verify in Grafana
```

### Feature 4: Health Monitoring Dashboard

**Service:** `aksh-health-dashboard.service` (timer: every 30 seconds)

**What it does:**
- Fetches provider status from `http://10.1.1.120:30843/status`
- Fetches cluster stats from `kubectl`
- Generates HTML dashboard at `/var/www/akash-health/index.html`
- Served via Cloudflare tunnel at `https://status.provider.reverb256.ca`

**Dashboard Metrics:**
- Active deployments
- Running pods
- Cluster nodes
- Active leases
- Available capacity

**Configuration:**
```nix
healthDashboard = {
  enable = true;
  updateInterval = 30;  # 30 seconds
  outputDir = "/var/www/akash-health";
};
```

**Testing:**
```bash
# Wait 30 seconds for dashboard generation
curl https://status.provider.reverb256.ca

# Verify metrics match provider status
```

### Feature 5: DNS Cleanup Automation

**Service:** `aksh-cloudflare-dns-cleanup.service` (timer: daily at 3 AM)

**What it does:**
- Runs daily at 3 AM
- Compares DNS records against active leases
- Deletes records older than grace period for ended leases
- 24-hour grace period before deletion

**Configuration:**
```nix
dnsCleanup = {
  enable = true;
  gracePeriod = 86400;  # 24 hours in seconds
  cleanupTime = "03:00:00";  # 3 AM daily
};
```

**Testing:**
```bash
# Create manual DNS record for ended lease (set created timestamp to 25h ago)
# Run cleanup
systemctl start akash-cloudflare-dns-cleanup

# Verify record deleted in Cloudflare dashboard
journalctl -u akash-cloudflare-dns-cleanup -n 50
```

### Feature 6: Status Page

**Service:** `akash-status-page.service` (timer: every 5 minutes)

**What it does:**
- Generates public-facing status page
- Shows provider info, GPU models, pricing
- Served via Cloudflare tunnel at `https://akash.reverb256.ca`

**Configuration:**
```nix
statusPage = {
  enable = true;
  updateInterval = 300;  # 5 minutes
  outputDir = "/var/www/akash-status";
};
```

**Testing:**
```bash
# Wait 10 seconds for page generation
curl https://akash.reverb256.ca
```

## Security Considerations

### Token Storage
- Stored via agenix at `/run/agenix/cloudflare-api-token`
- Only readable by root
- Never touches disk unencrypted

### Service Hardening
All services use systemd security hardening:
- `NoNewPrivileges` - Prevent privilege escalation
- `ProtectSystem` - Read-only filesystem (except write paths)
- `PrivateTmp` - Isolated `/tmp` directory
- `ProtectHome` - No access to user home directories
- `ReadWritePaths` - Limited to specific directories only

### Network Security
- All Cloudflare API calls use HTTPS
- Local provider access via NodePort (not public endpoints)
- No additional firewall ports opened (uses existing Cloudflare tunnel)
- Kubernetes RBAC: Services run with minimal required permissions

## Troubleshooting

### DNS Watcher Not Creating Records

```bash
# Check service status
systemctl status akash-cloudflare-dns-watcher

# Check logs
journalctl -u akash-cloudflare-dns-watcher -n 100

# Verify token
cat /run/agenix/cloudflare-api-token

# Test token manually
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $(cat /run/agenix/cloudflare-api-token)"

# Verify Kubernetes access
kubectl get deployments -n akash-services -l "akash.network=true"
```

### Metrics Not Appearing in Prometheus

```bash
# Check metrics file exists
cat /var/lib/prometheus/node-exporter/textfile-collector/cloudflare.prom

# Check file permissions
ls -la /var/lib/prometheus/node-exporter/textfile-collector/

# Check service logs
journalctl -u akash-cloudflare-metrics -n 50

# Verify Prometheus scraping
curl 'http://sentry:9090/api/v1/label/__name__/values' | grep cloudflare
```

### Dashboard Not Updating

```bash
# Check service status
systemctl status akash-health-dashboard

# Check timer is running
systemctl list-timers | grep dashboard

# Check output directory
ls -la /var/www/akash-health/

# Verify nginx is running
systemctl status nginx

# Check Cloudflare tunnel routes
curl https://status.provider.reverb256.ca
```

### Cleanup Not Removing Stale Records

```bash
# Run cleanup manually
systemctl start akash-cloudflare-dns-cleanup

# Check logs
journalctl -u akash-cloudflare-dns-cleanup -n 100

# Verify grace period setting
# (default is 24 hours, records younger than this won't be deleted)

# List all DNS records
curl -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $TOKEN" | jq '.result[] | {name, created_on}'
```

## Monitoring and Alerting

### Key Metrics to Monitor

```yaml
# DNS watcher processing
alert: DNSWatcherNotProcessing
expr: increase(cloudflare_dns_records_created[1h]) == 0
for: 2h
annotations:
  summary: "DNS watcher hasn't created any records in 2 hours"

# Cache purge failures
alert: CachePurgeFailing
expr: rate(cloudflare_cache_purge_errors[5m]) > 0.1
for: 10m
annotations:
  summary: "Cache purge error rate is high"

# Dashboard not updating
alert: DashboardNotUpdating
expr: time() - cloudflare_dashboard_last_update_timestamp > 300
for: 5m
annotations:
  summary: "Health dashboard hasn't updated in 5 minutes"
```

## Rollback

### Disable All Features

```nix
services.akash-cloudflare-integration.enable = false;
```

### Disable Specific Feature

```nix
services.akash-cloudflare-integration.dnsWatcher.enable = false;
```

### Manual DNS Cleanup

```bash
# List all DNS records
curl -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $TOKEN" | jq '.result[] | {id, name}'

# Delete specific record
curl -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $TOKEN"
```

## Architecture

### Integration Points

**With Akash Provider (Kubernetes):**
- **Kubernetes API**: Watch deployments in `akash-services` namespace
- **Provider HTTP endpoint**: `http://10.1.1.120:30843/status` (NodePort on Nexus)
- **Provider gRPC**: `grpc://10.1.1.120:30844` (NodePort on Nexus)
- **Ingress patterns**: Extract tenant names from `*.ingress.reverb256.ca`

**With Cloudflare:**
- **API Endpoint**: `https://api.cloudflare.com/client/v4/`
- **Zone ID**: Retrieved via API from domain name
- **Token**: Stored via agenix at `/run/agenix/cloudflare-api-token`
- **DNS API**: CRUD operations on `reverb256.ca` zone
- **Cache API**: Purge operations with `files` parameter

**With Monitoring:**
- **Textfile Collector**: `/var/lib/prometheus/node-exporter/textfile-collector/`
- **Scrape Pattern**: Already configured - node-exporter auto-scrapes this directory
- **Metrics Format**: Standard Prometheus exposition format

## Success Criteria

### Feature 1: Automated Tenant DNS Setup
- ✅ DNS records created within 30 seconds of deployment
- ✅ DNS resolves correctly
- ✅ Records deleted within 1 hour of lease end
- ✅ Zero manual DNS management

### Feature 2: Smart Cache Invalidation
- ✅ Cache purged within 10 seconds of deployment
- ✅ Only tenant's URLs purged (not entire zone)
- ✅ Fresh content served after purge
- ✅ Zero 404 errors from stale cache

### Feature 3: Prometheus Integration
- ✅ Metrics exported every 5 minutes
- ✅ All 6 metrics tracked
- ✅ Metrics visible in Prometheus UI
- ✅ Grafana dashboard created

### Feature 4: Health Monitoring Dashboard
- ✅ Dashboard updates every 30 seconds
- ✅ All 6 metrics displayed
- ✅ Accessible via Cloudflare tunnel
- ✅ Responsive design

### Feature 5: DNS Cleanup Automation
- ✅ Runs daily at 3 AM
- ✅ Deletes records older than 24 hours
- ✅ Preserves active lease records
- ✅ Zero false positives

### Feature 6: Status Page
- ✅ Page updates every 5 minutes
- ✅ Displays provider info, GPU models, pricing
- ✅ Publicly accessible
- ✅ Professional appearance

## Further Reading

- **Cloudflare API Documentation**: https://developers.cloudflare.com/api/
- **Akash Provider Docs**: https://akash.network/docs/providers
- **Prometheus Textfile Collector**: https://github.com/prometheus/node_exporter#textfile-collector
- **Agenix Secrets**: https://github.com/ryantm/agenix

## Version History

- **v1.0.0** (2026-03-19): Initial release with all 6 features
