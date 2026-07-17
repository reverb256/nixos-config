#!/usr/bin/env bash
# add-friendly-route.sh - Quick helper to add friendly routes to Caddy ingress
#
# Usage: ./add-friendly-route.sh <name> <backend-service> [namespace] [port]
#
# Examples:
#   ./add-friendly-route.sh home home-assistant default 8123
#   ./add-friendly-route.sh vault vaultwarden default 80
#   ./add-friendly-route.sh ai ai-inference default 8080

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CONFIGMAP="${CONFIGMAP:-/etc/nixos/kubernetes-manifests/ingress/02-configmap.yaml}"
NAMESPACE="${3:-default}"
PORT="${4:-80}"

# Helper functions
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

# Validate inputs
if [ $# -lt 2 ]; then
  log_error "Usage: $0 <friendly-name> <backend-service> [namespace] [port]"
  echo ""
  echo "Examples:"
  echo "  $0 home home-assistant default 8123"
  echo "  $0 ai ai-inference default 8080"
  echo "  $0 vault vaultwarden default 80"
  echo ""
  echo "This will add a route like:"
  echo "  <friendly-name>.cluster.local → <backend-service>.<namespace>.svc.cluster.local:<port>"
  exit 1
fi

FRIENDLY_NAME="$1"
BACKEND_SERVICE="$2"
BACKEND_FQDN="${BACKEND_SERVICE}.${NAMESPACE}.svc.cluster.local"

# Validate friendly name (lowercase alphanumeric and hyphens only)
if [[ ! "$FRIENDLY_NAME" =~ ^[a-z0-9-]+$ ]]; then
  log_error "Friendly name must be lowercase alphanumeric with hyphens only"
  exit 1
fi

# Check if configmap exists
if [ ! -f "$CONFIGMAP" ]; then
  log_error "ConfigMap not found: $CONFIGMAP"
  exit 1
fi

# Check if route already exists
if grep -q "${FRIENDLY_NAME}\.cluster\.local" "$CONFIGMAP"; then
  log_warn "Route for ${FRIENDLY_NAME}.cluster.local already exists!"
  read -p "Overwrite? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Aborted"
    exit 0
  fi
fi

# Generate the route snippet
cat <<ROUTE

# ================================================================================
# ROUTE: ${FRIENDLY_NAME}.cluster.local
# Backend: ${BACKEND_FQDN}:${PORT}
# Added: $(date)
# ================================================================================

${FRIENDLY_NAME}.cluster.local {
  reverse_proxy ${BACKEND_FQDN}:${PORT} {
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Host {host}
    header_up X-Forwarded-Proto {scheme}
  }
}

ROUTE

# Ask for confirmation
echo ""
log_info "Ready to add route for ${FRIENDLY_NAME}.cluster.local"
echo "  Backend: ${BACKEND_FQDN}:${PORT}"
echo ""
read -p "Add this route to ${CONFIGMAP}? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  log_info "Aborted"
  exit 0
fi

# Backup configmap
cp "$CONFIGMAP" "${CONFIGMAP}.backup.$(date +%Y%m%d-%H%M%S)"
log_info "Backed up to ${CONFIGMAP}.backup.$(date +%Y%m%d-%H%M%S)"

# Add route to configmap
# Find the line with "## KUBERNETES DASHBOARD" and insert before it
if grep -q "## KUBERNETES DASHBOARD" "$CONFIGMAP"; then
  # Insert before the Kubernetes dashboard section
  awk "
    /## KUBERNETES DASHBOARD/ {
      print \"\n\"
      print \"# ================================================================================\"
      print \"# ROUTE: ${FRIENDLY_NAME}.cluster.local\"
      print \"\"
      print \"${FRIENDLY_NAME}.cluster.local {\"
      print \"  reverse_proxy ${BACKEND_FQDN}:${PORT} {\"
      print \"    header_up Host {host}\"
      print \"    header_up X-Real-IP {remote_host}\"
      print \"    header_up X-Forwarded-For {remote_host}\"
      print \"  }\"
      print \"}\"
      print \"\"
    }
    { print }
  " "$CONFIGMAP" > "${CONFIGMAP}.tmp" && mv "${CONFIGMAP}.tmp" "$CONFIGMAP"
else
  # Append to end of file
  echo "" >> "$CONFIGMAP"
  echo "# Route for ${FRIENDLY_NAME}.cluster.local" >> "$CONFIGMAP"
  echo "${FRIENDLY_NAME}.cluster.local {" >> "$CONFIGMAP"
  echo "  reverse_proxy ${BACKEND_FQDN}:${PORT} {" >> "$CONFIGMAP"
  echo "    header_up Host {host}" >> "$CONFIGMAP"
  echo "    header_up X-Real-IP {remote_host}" >> "$CONFIGMAP"
  echo "  }" >> "$CONFIGMAP"
  echo "}" >> "$CONFIGMAP"
fi

log_info "Route added to $CONFIGMAP"
echo ""
echo "Next steps:"
echo "  1. Review the changes: cat $CONFIGMAP | tail -30"
echo "  2. Apply to cluster: kubectl apply -f $CONFIGMAP"
echo "  3. Restart Caddy: kubectl -n ingress-system rollout restart daemonset/caddy-ingress"
echo "  4. Test: curl -H 'Host: ${FRIENDLY_NAME}.cluster.local' http://10.1.1.120:30080/"
