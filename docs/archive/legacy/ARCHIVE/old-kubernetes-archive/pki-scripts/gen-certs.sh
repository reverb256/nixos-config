#!/usr/bin/env bash
# =============================================================================
# Kubernetes HA PKI Certificate Generation Script
# =============================================================================
# Generates all certificates needed for HA Kubernetes cluster using cfssl
#
# Usage: ./gen-certs.sh [output-dir]
#   output-dir: Where to store generated certificates (default: ./output)
#
# Requirements:
#   - cfssl: CloudFlare's SSL toolkit (https://github.com/cloudflare/cfssl)
#   - cfssljson: JSON processor for cfssl
#
# Output:
#   - ca.pem: Certificate Authority certificate
#   - ca-key.pem: Certificate Authority private key (agenix encrypted)
#   - apiserver.pem: API server certificate
#   - apiserver-key.pem: API server private key (agenix encrypted)
#   - etcd-peer.pem: etcd peer certificate (shared)
#   - etcd-peer-key.pem: etcd peer private key (agenix encrypted)
#   - etcd-*.pem: etcd server certificates (per-node)
#   - etcd-*-key.pem: etcd server private keys (agenix encrypted)
#   - admin.pem: Admin client certificate
#   - admin-key.pem: Admin private key (agenix encrypted)
#   - controller-manager.pem: Controller manager certificate
#   - controller-manager-key.pem: Controller manager private key (agenix encrypted)
#   - scheduler.pem: Scheduler certificate
#   - scheduler-key.pem: Scheduler private key (agenix encrypted)
#
# =============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR/output}"
CERT_VALIDITY="87600h"  # 10 years
PKI_DIR="$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_error "$1 is required but not installed"
        log_info "Install with: nix-shell -p cfssl"
        exit 1
    fi
}

create_output_dir() {
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR/certs"
    mkdir -p "$OUTPUT_DIR/private"
    mkdir -p "$OUTPUT_DIR/agenix-seeds"
}

generate_ca() {
    log_info "Generating Certificate Authority..."

    cfssl gencert \
        -initca "$PKI_DIR/ca-csr.json" | \
        cfssljson -bare "$OUTPUT_DIR/ca"

    mv "$OUTPUT_DIR/ca.pem" "$OUTPUT_DIR/certs/ca.pem"
    mv "$OUTPUT_DIR/ca-key.pem" "$OUTPUT_DIR/private/ca-key.pem"

    log_success "CA certificate generated: $OUTPUT_DIR/certs/ca.pem"
    log_warn "CA private key: $OUTPUT_DIR/private/ca-key.pem (encrypt with agenix)"
}

generate_apiserver_cert() {
    log_info "Generating API Server certificate..."

    cfssl gencert \
        -ca="$OUTPUT_DIR/certs/ca.pem" \
        -ca-key="$OUTPUT_DIR/private/ca-key.pem" \
        -config="$PKI_DIR/ca-config.json" \
        -profile=kubernetes \
        -hostname="$(
            IFS=,
            echo "${hosts[*]}"
        )" \
        "$PKI_DIR/apiserver-csr.json" | \
        cfssljson -bare "$OUTPUT_DIR/apiserver"

    mv "$OUTPUT_DIR/apiserver.pem" "$OUTPUT_DIR/certs/apiserver.pem"
    mv "$OUTPUT_DIR/apiserver-key.pem" "$OUTPUT_DIR/private/apiserver-key.pem"

    log_success "API Server certificate generated"
}

generate_etcd_peer_cert() {
    log_info "Generating etcd peer certificate..."

    cfssl gencert \
        -ca="$OUTPUT_DIR/certs/ca.pem" \
        -ca-key="$OUTPUT_DIR/private/ca-key.pem" \
        -config="$PKI_DIR/ca-config.json" \
        -profile=peer \
        "$PKI_DIR/etcd-peer-csr.json" | \
        cfssljson -bare "$OUTPUT_DIR/etcd-peer"

    mv "$OUTPUT_DIR/etcd-peer.pem" "$OUTPUT_DIR/certs/etcd-peer.pem"
    mv "$OUTPUT_DIR/etcd-peer-key.pem" "$OUTPUT_DIR/private/etcd-peer-key.pem"

    log_success "etcd peer certificate generated"
}

generate_etcd_server_cert() {
    local node="$1"
    local csr_file="$2"

    log_info "Generating etcd server certificate for $node..."

    cfssl gencert \
        -ca="$OUTPUT_DIR/certs/ca.pem" \
        -ca-key="$OUTPUT_DIR/private/ca-key.pem" \
        -config="$PKI_DIR/ca-config.json" \
        -profile=server \
        "$csr_file" | \
        cfssljson -bare "$OUTPUT_DIR/etcd-$node"

    mv "$OUTPUT_DIR/etcd-$node.pem" "$OUTPUT_DIR/certs/etcd-$node.pem"
    mv "$OUTPUT_DIR/etcd-$node-key.pem" "$OUTPUT_DIR/private/etcd-$node-key.pem"

    log_success "etcd server certificate for $node generated"
}

generate_client_cert() {
    local name="$1"
    local csr_file="$2"

    log_info "Generating client certificate for $name..."

    cfssl gencert \
        -ca="$OUTPUT_DIR/certs/ca.pem" \
        -ca-key="$OUTPUT_DIR/private/ca-key.pem" \
        -config="$PKI_DIR/ca-config.json" \
        -profile=client \
        "$csr_file" | \
        cfssljson -bare "$OUTPUT_DIR/$name"

    mv "$OUTPUT_DIR/$name.pem" "$OUTPUT_DIR/certs/$name.pem"
    mv "$OUTPUT_DIR/$name-key.pem" "$OUTPUT_DIR/private/$name-key.pem"

    log_success "Client certificate for $name generated"
}

generate_agénix_template() {
    local key_file="$1"
    local template_name="$2"

    cp "$key_file" "$OUTPUT_DIR/agenix-seeds/$template-name.age"

    log_info "Created agenix template: $OUTPUT_DIR/agenix-seeds/$template_name.age"
}

print_summary() {
    cat <<EOF

${GREEN}═══════════════════════════════════════════════════════════════════${NC}
${GREEN}Certificate Generation Complete${NC}
${GREEN}═══════════════════════════════════════════════════════════════════${NC}

${BLUE}Output Directory:${NC} $OUTPUT_DIR

${BLUE}Certificates (public):${NC}
  - certs/ca.pem                    (Certificate Authority)
  - certs/apiserver.pem             (Kubernetes API Server)
  - certs/etcd-peer.pem             (etcd peer cluster)
  - certs/etcd-zephyr.pem           (etcd server - Zephyr)
  - certs/etcd-nexus.pem            (etcd server - Nexus)
  - certs/etcd-sentry.pem           (etcd server - Sentry)
  - certs/admin.pem                 (Cluster admin)
  - certs/controller-manager.pem    (Kube Controller Manager)
  - certs/scheduler.pem             (Kube Scheduler)

${BLUE}Private Keys (encrypt with agenix):${NC}
  - private/ca-key.pem
  - private/apiserver-key.pem
  - private/etcd-peer-key.pem
  - private/etcd-zephyr-key.pem
  - private/etcd-nexus-key.pem
  - private/etcd-sentry-key.pem
  - private/admin-key.pem
  - private/controller-manager-key.pem
  - private/scheduler-key.pem

${YELLOW}Next Steps:${NC}
  1. Review certificates: cfssl certinfo -cert $OUTPUT_DIR/certs/apiserver.pem
  2. Encrypt private keys with agenix
  3. Copy certificates to /etc/kubernetes/pki on each node
  4. Update kubernetes-ha.nix with certificate paths
  5. Deploy with: just deploy

${YELLOW}agenix encryption example:${NC}
  agenix -e /etc/nixos/secrets/kubernetes-ca.age
  # Paste contents of: $OUTPUT_DIR/private/ca-key.pem

${GREEN}═══════════════════════════════════════════════════════════════════${NC}
EOF
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   Kubernetes HA PKI Certificate Generation                     ║"
    echo "║   Using cfssl for production-ready certificates               ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Check prerequisites
    log_info "Checking prerequisites..."
    check_command cfssl
    check_command cfssljson

    # Create output directory
    create_output_dir
    log_info "Output directory: $OUTPUT_DIR"

    # Generate certificates
    generate_ca
    generate_apiserver_cert
    generate_etcd_peer_cert
    generate_etcd_server_cert "zephyr" "$PKI_DIR/etcd-zephyr-csr.json"
    generate_etcd_server_cert "nexus" "$PKI_DIR/etcd-nexus-csr.json"
    generate_etcd_server_cert "sentry" "$PKI_DIR/etcd-sentry-csr.json"
    generate_client_cert "admin" "$PKI_DIR/admin-csr.json"
    generate_client_cert "controller-manager" "$PKI_DIR/controller-manager-csr.json"
    generate_client_cert "scheduler" "$PKI_DIR/scheduler-csr.json"

    # Print summary
    print_summary
}

main "$@"
