# GlitchTip Kubernetes Migration

## Overview
Migrates GlitchTip error tracking from systemd/Podman to Kubernetes.

## Components
- **PostgreSQL**: StatefulSet with PVC (fast-local-ssd)
- **Redis**: Deployment with PVC (fast-local-ssd)
- **Web**: Deployment (main UI)
- **Worker**: Deployment (async task processing)

## Migration Steps

### 1. Create Secrets from Agenix
```bash
# Get the database password
DB_PASS=$(cat /run/agenix/glitchtip-db-password)

# Get the secret key
SECRET_KEY=$(cat /run/agenix/glitchtip-secret-key)

# Create the secret
kubectl create secret generic glitchtip-secrets \
  -n glitchtip \
  --from-literal=postgres-password="$DB_PASS" \
  --from-literal=secret-key="$SECRET_KEY"
```

### 2. Backup Existing Data
```bash
# Backup PostgreSQL data
podman exec glitchtip-postgres pg_dump -U glitchtip glitchtip > /tmp/glitchtip-backup.sql

# Backup Redis data (optional)
cp -r /var/lib/glitchtip/redis /var/lib/glitchtip/redis.backup
```

### 3. Deploy to Kubernetes
```bash
kubectl apply -f /etc/nixos/kubernetes-manifests/glitchtip/
```

### 4. Restore Data (if needed)
```bash
# Restore PostgreSQL backup
kubectl cp /tmp/glitchtip-backup.sql glitchtip/postgres-0:/tmp/backup.sql
kubectl exec -n glitchtip postgres-0 -- psql -U glitchtip glitchtip < /tmp/backup.sql
```

### 5. Verify Deployment
```bash
# Check pods
kubectl get pods -n glitchtip

# Check logs
kubectl logs -n glitchtip -f deployment/web

# Access via port-forward (for testing)
kubectl port-forward -n glitchtip deployment/web 8000:8000
```

### 6. Update Ingress
Add route to Caddy ingress for external access.

### 7. Disable Systemd Services (After Verification)
```bash
sudo systemctl disable --now glitchtip-postgres
sudo systemctl disable --now glitchtip-redis
sudo systemctl disable --now glitchtip-web
sudo systemctl disable --now glitchtip-worker
sudo systemctl disable --now glitchtip-pod
```

## Storage
- PostgreSQL: 10Gi PVC (fast-local-ssd)
- Redis: 2Gi PVC (fast-local-ssd)

## Services
- `postgres:5432` - ClusterIP
- `redis:6379` - ClusterIP
- `web:8000` - ClusterIP
