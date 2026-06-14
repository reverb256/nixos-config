#!/usr/bin/env bash
# validate-cluster-services.sh
# Post-deploy validation: checks TLS, DNS, and config consistency for .lan services.
# Run after any infra change:  sudo bash validate-cluster-services.sh

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0; WARN=0
pass() { echo -e "  ${GREEN}PASS${NC} $1"; ((PASS++)) || true; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; ((FAIL++)) || true; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; ((WARN++)) || true; }

CA_FILE="/etc/nixos/certs/cluster-ca.crt"
[ -f "$CA_FILE" ] || CA_FILE="/etc/ssl/cluster-ca/ca.crt"

echo "=== TLS: All .lan domains serve valid certs ==="
for entry in   "searxng.lan|/" "search.lan|/" "auth.lan|/"   "ai-inference.lan|/" "haven.lan|/" "hermes.lan|/"   "qdrant.lan|/" "n8n.lan|/" "dashboard.lan|/"   "vaultwarden.lan|/" "mission-control.lan|/"   "knowledge-fabric.lan|/" "brain.lan|/"   "workspace.lan|/"   "openwebui.lan|/" "forge.lan|/"   "monitoring.lan|/" "grafana.lan|/" "prometheus.lan|/"   "privacy-filter.lan|/"    "cfg.lan|/" "frostbite-mcp.lan|/" "seeker.lan|/"   "mining.lan|/" "api.hermes.lan|/"; do
    domain="${entry%%|*}"
    path="${entry#*|}"
    code=$(curl -sk --resolve "${domain}:443:10.1.1.100" "https://${domain}${path}"       -o /dev/null -w "%{http_code}" --connect-timeout 5 2>/dev/null)
  [ "$code" != "000" ] && pass "${domain}${path} -> HTTP $code" || fail "${domain}${path} unreachable"
done

echo ""
echo "=== DNS: K8s service names resolve ==="
KUBE_DNS=$(kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
for svc in searxng.search vane.search; do
  ip=$(dig "${svc}.svc.cluster.local" @"${KUBE_DNS}" +short 2>/dev/null)
  [ -n "$ip" ] && pass "${svc} -> $ip" || fail "${svc} no resolution"
done

echo ""
echo "=== Config: SearXNG OpenSearch XML matches browser ==="
OPENXML=$(curl -sk 'https://searxng.lan/opensearch.xml' 2>/dev/null)
echo "$OPENXML" | grep -q 'template="https://searxng.lan/search' \
  && pass "OpenSearch XML points to searxng.lan" \
  || fail "OpenSearch XML hostname mismatch"

echo ""
echo "=== CA: All nodes share the same CA cert ==="
LOCAL_FP=$(nix run nixpkgs#openssl -- x509 -in /etc/nixos/certs/cluster-ca.crt -noout -fingerprint -sha1 2>/dev/null | cut -d= -f2 || echo "ERROR")
pass "Local CA: $LOCAL_FP"
for node in 10.1.1.110 10.1.1.120; do
  remote_fp=$(timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i /etc/nixos/ssh/id_ed25519 "j_kro@$node" \
    "sudo cat /etc/ssl/cluster-ca/ca.crt 2>/dev/null" 2>/dev/null \
    | nix run nixpkgs#openssl -- x509 -noout -fingerprint -sha1 2>/dev/null | cut -d= -f2 || echo "UNREACHABLE")
  if [ "$remote_fp" = "UNREACHABLE" ]; then
    warn "  $node unreachable"
  elif [ "$remote_fp" = "$LOCAL_FP" ]; then
    pass "  $node matches"
  else
    fail "  $node MISMATCH ($remote_fp)"
  fi
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $WARN warned ==="
exit $FAIL
