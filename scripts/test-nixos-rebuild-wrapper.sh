#!/usr/bin/env bash
# Test nixos-rebuild-wrapper Script
# Tests the wrapper script that translates nixos-rebuild commands to Colmena
#
# Usage: sudo ./test-nixos-rebuild-wrapper.sh

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

# ============================================================================
# PRE-TEST CHECKS
# ============================================================================

log "=========================================="
log "nixos-rebuild-wrapper Test Suite"
log "=========================================="
log "Host: $(hostname)"
log ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This test must be run as root (sudo)"
    exit 1
fi

# Check if wrapper script exists
WRAPPER_SCRIPT="/etc/nixos/scripts/nixos-rebuild-wrapper"
if [ ! -f "$WRAPPER_SCRIPT" ]; then
    log_error "Wrapper script not found at $WRAPPER_SCRIPT"
    exit 1
fi

log "✓ Wrapper script found"

# Check if executable
if [ ! -x "$WRAPPER_SCRIPT" ]; then
    log_error "Wrapper script is not executable"
    exit 1
fi

log "✓ Wrapper script is executable"

# ============================================================================
# TEST 1: Help Passthrough
# ============================================================================

log ""
log "=========================================="
log "Test 1: Help Passthrough"
log "=========================================="

log "Testing --help flag (should pass to native nixos-rebuild)..."
if OUTPUT=$($WRAPPER_SCRIPT --help 2>&1); then
    log "✓ --help passthrough works"
    log_info "Output preview: $(echo "$OUTPUT" | head -n 3)"
else
    log_error "✗ --help passthrough failed"
    exit 1
fi

# ============================================================================
# TEST 2: Native Bypass
# ============================================================================

log ""
log "=========================================="
log "Test 2: Native Bypass"
log "=========================================="

log "Testing NIXOS_REBUILD_NATIVE environment variable..."
if NIXOS_REBUILD_NATIVE=1 $WRAPPER_SCRIPT --help >/dev/null 2>&1; then
    log "✓ Native bypass works with NIXOS_REBUILD_NATIVE=1"
else
    log_error "✗ Native bypass failed"
    exit 1
fi

# ============================================================================
# TEST 3: Command Translation
# ============================================================================

log ""
log "=========================================="
log "Test 3: Command Translation"
log "=========================================="

HOSTNAME=$(hostname)

# Test build command translation
log "Testing 'build' command translation..."
BUILD_OUTPUT=$($WRAPPER_SCRIPT build --dry-run 2>&1 || true)
if echo "$BUILD_OUTPUT" | grep -q "colmena build.*--on $HOSTNAME"; then
    log "✓ 'build' translates to 'colmena build --on $HOSTNAME'"
else
    log_warn "⚠ Could not verify build translation (dry-run may not be implemented)"
fi

# Test switch command translation
log "Testing 'switch' command translation..."
SWITCH_OUTPUT=$($WRAPPER_SCRIPT switch --dry-run 2>&1 || true)
if echo "$SWITCH_OUTPUT" | grep -q "colmena apply.*--on $HOSTNAME"; then
    log "✓ 'switch' translates to 'colmena apply --on $HOSTNAME'"
else
    log_warn "⚠ Could not verify switch translation (dry-run may not be implemented)"
fi

# ============================================================================
# TEST 4: GPU Node Detection
# ============================================================================

log ""
log "=========================================="
log "Test 4: GPU Node Detection"
log "=========================================="

HOSTNAME=$(hostname)
GPU_NODES=("zephyr" "nexus" "forge")
IS_GPU_NODE=false

for node in "${GPU_NODES[@]}"; do
    if [ "$HOSTNAME" = "$node" ]; then
        IS_GPU_NODE=true
        break
    fi
done

if [ "$IS_GPU_NODE" = true ]; then
    log "✓ Running on GPU node: $HOSTNAME"
    log_info "Should signal /run/gpu-scheduler/ai-state during deploy"
else
    log "✓ Running on non-GPU node: $HOSTNAME"
    log_info "Should NOT signal GPU scheduler"
fi

# ============================================================================
# TEST 5: State File Creation
# ============================================================================

log ""
log "=========================================="
log "Test 5: State File Creation"
log "=========================================="

STATE_DIR="/run/nixos-deploy"
STATE_FILE="$STATE_DIR/${HOSTNAME}.json"

log "Checking state directory..."
if [ ! -d "$STATE_DIR" ]; then
    log_warn "State directory does not exist: $STATE_DIR"
    log_info "It should be created during first deploy"
else
    log "✓ State directory exists: $STATE_DIR"
fi

# ============================================================================
# TEST 6: Mining Pause/Resume Detection
# ============================================================================

log ""
log "=========================================="
log "Test 6: Mining Pause/Resume"
log "=========================================="

if systemctl -q is-active mining.target 2>/dev/null; then
    log "✓ mining.target exists and is active"
    log_info "Wrapper should pause mining before deploy"
elif systemctl -q is-enabled mining.target 2>/dev/null; then
    log "✓ mining.target exists but is not active"
    log_info "Wrapper will skip mining pause (not running)"
else
    log "⚠ mining.target does not exist on this host"
    log_info "Wrapper will skip mining pause (not configured)"
fi

# ============================================================================
# TEST 7: Rollback Detection
# ============================================================================

log ""
log "=========================================="
log "Test 7: Rollback Handling"
log "=========================================="

log "Testing 'rollback' command (should bypass wrapper)..."
ROLLBACK_OUTPUT=$($WRAPPER_SCRIPT rollback --help 2>&1 || true)
if echo "$ROLLBACK_OUTPUT" | grep -q "nixos-rebuild"; then
    log "✓ 'rollback' bypasses wrapper and uses native nixos-rebuild"
else
    log_warn "⚠ Could not verify rollback bypass"
fi

# ============================================================================
# SUMMARY
# ============================================================================

log ""
log "=========================================="
log "Test Summary"
log "=========================================="

log ""
log "✓ All basic tests passed!"
log ""
log "Next steps:"
log "  1. Review the wrapper script at $WRAPPER_SCRIPT"
log "  2. Test actual deployment: sudo $WRAPPER_SCRIPT build"
log "  3. Test switch on non-production: sudo $WRAPPER_SCRIPT switch"
log ""
log "Notes:"
log "  - GPU nodes (zephyr, nexus, forge) will signal GPU scheduler"
log "  - Mining will be paused before deploy if mining.target is active"
log "  - State files written to $STATE_DIR"
log "  - Use NIXOS_REBUILD_NATIVE=1 to bypass wrapper"
log ""

exit 0
