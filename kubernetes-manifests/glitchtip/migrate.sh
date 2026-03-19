#!/usr/bin/env bash
set -euo pipefail

# GlitchTip Kubernetes Migration Script
# Migrates GlitchTip from systemd/Podman to Kubernetes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="glitchtip"

echo "=== GlitchTip Kubernetes Migration ==="
echo ""

# Check if namespace exists, create manifests first if not
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Creating namespace and base resources..."
    kubectl apply -f "$SCRIPT_DIR/00-namespace.yaml"
fi

# Generate new secure secrets
echo "Step 1: Creating Kubernetes secrets..."
DB_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
SECRET_KEY=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-50)

echo "  Generated new secrets for Kubernetes deployment"

# Create the Kubernetes secret
kubectl create secret generic glitchtip-secrets \
    -n "$NAMESPACE" \
    --from-literal=postgres-password="$DB_PASS" \
    --from-literal=secret-key="$SECRET_KEY" \
    --from-literal=database-url="postgres://glitchtip:${DB_PASS}@postgres:5432/glitchtip" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "  Secrets created"
echo ""

# Backup existing data
echo "Step 2: Backing up existing data..."
BACKUP_DIR="/tmp/glitchtip-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Check if GlitchTip postgres is running and backup
if systemctl is-active --quiet glitchtip-postgres; then
    echo "  Backing up PostgreSQL from running container..."
    # Find the postgres container
    POSTGRES_CONTAINER=$(podman ps --filter "ancestor=postgres:16-alpine" --format "{{.Names}}" | grep -i postgres | head -1)

    if [[ -n "$POSTGRES_CONTAINER" ]]; then
        podman exec "$POSTGRES_CONTAINER" pg_dump -U glitchtip glitchtip > "$BACKUP_DIR/glitchtip.sql" 2>/dev/null && echo "  PostgreSQL backup complete" || echo "  Warning: PostgreSQL backup failed"
    else
        echo "  Warning: Could not find PostgreSQL container"
    fi
else
    echo "  GlitchTip PostgreSQL not running, skipping backup"
fi

# Backup data directories
echo "  Backing up data directories..."
cp -r /var/lib/glitchtip/postgres "$BACKUP_DIR/postgres-data" 2>/dev/null || echo "  Warning: Could not backup postgres data directory"
cp -r /var/lib/glitchtip/redis "$BACKUP_DIR/redis-data" 2>/dev/null || echo "  Warning: Could not backup redis data directory"

echo "  Backup location: $BACKUP_DIR"
echo ""

# Deploy Kubernetes manifests
echo "Step 3: Deploying to Kubernetes..."
kubectl apply -f "$SCRIPT_DIR/02-postgres-statefulset.yaml"
kubectl apply -f "$SCRIPT_DIR/03-redis-deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/04-web-deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/05-worker-deployment.yaml"
echo ""

# Wait for postgres pod to be ready
echo "Step 4: Waiting for PostgreSQL pod to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=180s || {
    echo "  Warning: PostgreSQL pod not ready within timeout"
    echo "  Check pods with: kubectl get pods -n $NAMESPACE"
}
echo ""

# Restore data if backup was successful
if [[ -f "$BACKUP_DIR/glitchtip.sql" ]]; then
    echo "Step 5: Restoring PostgreSQL data..."

    # Get the postgres pod name
    POSTGRES_POD=$(kubectl get pod -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -n "$POSTGRES_POD" ]]; then
        # Copy backup to pod
        kubectl cp "$BACKUP_DIR/glitchtip.sql" "$NAMESPACE/$POSTGRES_POD:/tmp/backup.sql" 2>/dev/null || echo "  Warning: Could not copy backup to pod"

        # Restore data
        kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U glitchtip glitchtip < /tmp/backup.sql 2>/dev/null && echo "  Data restore complete" || echo "  Warning: Could not restore data (may need manual intervention)"
    else
        echo "  Warning: Could not find PostgreSQL pod for restore"
    fi
fi

echo ""
echo "=== Migration Deployed ==="
echo ""
echo "Current status:"
kubectl get pods -n "$NAMESPACE"
echo ""
echo "Next steps:"
echo "1. Check logs: kubectl logs -n $NAMESPACE deployment/web"
echo "2. Port-forward for testing: kubectl port-forward -n $NAMESPACE deployment/web 8000:8000"
echo "3. Access at: http://localhost:8000"
echo ""
echo "If everything works, disable old systemd services:"
echo "  sudo systemctl disable --now glitchtip-postgres glitchtip-redis glitchtip-web glitchtip-worker glitchtip-pod"
echo ""
echo "If data migration failed, you can manually restore from:"
echo "  $BACKUP_DIR"
echo ""
