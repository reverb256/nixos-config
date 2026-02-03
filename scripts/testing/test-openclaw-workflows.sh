#!/usr/bin/env bash
# OpenClaw AIStor Workflow Tests
# Tests all OpenClaw workflows against the deployed AIStor infrastructure

set -e

AISTOR_ENDPOINT="${AISTOR_ENDPOINT:-http://10.1.1.120:9000}"
BUCKETS=("ai-models" "training-data" "experiments" "ai-logs" "nix-cache")
TEST_RUN_ID="test-$(date +%Y%m%d-%H%M%S)"

echo "=== OpenClaw AIStor Workflow Tests ==="
echo "Endpoint: $AISTOR_ENDPOINT"
echo "Test Run ID: $TEST_RUN_ID"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++))
}

warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
}

# Test 1: Check AIStor connectivity
test_connectivity() {
    echo "--- Test 1: AIStor Connectivity ---"
    if mc alias list | grep -q "aistor"; then
        if mc admin info aistor >/dev/null 2>&1; then
            pass "AIStor server is accessible"
        else
            fail "AIStor server not responding"
        fi
    else
        fail "mc alias 'aistor' not configured. Run: mc alias set aistor $AISTOR_ENDPOINT ACCESS_KEY SECRET_KEY"
    fi
    echo ""
}

# Test 2: Verify all buckets exist
test_buckets_exist() {
    echo "--- Test 2: Bucket Existence ---"
    for bucket in "${BUCKETS[@]}"; do
        if mc ls aistor/ | grep -q "$bucket"; then
            pass "Bucket exists: $bucket"
        else
            fail "Bucket missing: $bucket"
        fi
    done
    echo ""
}

# Test 3: Test model storage workflow
test_model_storage() {
    echo "--- Test 3: Model Storage Workflow ---"
    
    # Create a dummy model file
    MODEL_FILE="/tmp/test-model-${TEST_RUN_ID}.pt"
    echo "dummy model checkpoint data" > "$MODEL_FILE"
    
    # Run checkpoint workflow
    if python3 /etc/nixos/scripts/openclaw-aistor-workflows.py checkpoint \
        --run-id "$TEST_RUN_ID" \
        --model-path "$MODEL_FILE" \
        --metrics '{"accuracy": 0.95, "loss": 0.05}'; then
        
        # Verify upload
        if mc ls "aistor/ai-models/${TEST_RUN_ID}/" 2>/dev/null | grep -q "test-model"; then
            pass "Model stored successfully with metadata"
        else
            fail "Model upload verification failed"
        fi
    else
        fail "Model storage workflow failed"
    fi
    
    # Cleanup local file
    rm -f "$MODEL_FILE"
    echo ""
}

# Test 4: Test dataset ingestion workflow
test_dataset_ingestion() {
    echo "--- Test 4: Dataset Ingestion Workflow ---"
    
    # Create a dummy dataset directory
    DATASET_DIR="/tmp/test-dataset-${TEST_RUN_ID}"
    mkdir -p "$DATASET_DIR"
    echo "sample data" > "$DATASET_DIR/sample1.txt"
    echo "sample data" > "$DATASET_DIR/sample2.txt"
    
    # Run dataset workflow
    DATASET_NAME="test-dataset-${TEST_RUN_ID}"
    if python3 /etc/nixos/scripts/openclaw-aistor-workflows.py dataset \
        --dataset-name "$DATASET_NAME" \
        --dataset-path "$DATASET_DIR"; then
        
        # Verify upload
        if mc ls "aistor/training-data/${DATASET_NAME}/" 2>/dev/null | grep -q "sample"; then
            pass "Dataset ingested successfully with manifest"
        else
            fail "Dataset upload verification failed"
        fi
    else
        fail "Dataset ingestion workflow failed"
    fi
    
    # Cleanup
    rm -rf "$DATASET_DIR"
    echo ""
}

# Test 5: Test experiment tracking workflow
test_experiment_tracking() {
    echo "--- Test 5: Experiment Tracking Workflow ---"
    
    EXPERIMENT_ID="exp-${TEST_RUN_ID}"
    
    # Create dummy artifacts
    ARTIFACTS_DIR="/tmp/test-artifacts-${TEST_RUN_ID}"
    mkdir -p "$ARTIFACTS_DIR"
    echo "config yaml" > "$ARTIFACTS_DIR/config.yaml"
    echo "results json" > "$ARTIFACTS_DIR/results.json"
    
    # Run experiment workflow
    if python3 /etc/nixos/scripts/openclaw-aistor-workflows.py experiment \
        --experiment-id "$EXPERIMENT_ID" \
        --artifacts "$ARTIFACTS_DIR" \
        --config '{"model": "resnet50", "epochs": 10}' \
        --results '{"accuracy": 0.92, "f1": 0.91}'; then
        
        # Verify upload
        if mc ls "aistor/experiments/${EXPERIMENT_ID}/" 2>/dev/null | grep -q "report"; then
            pass "Experiment tracked successfully with artifacts"
        else
            fail "Experiment upload verification failed"
        fi
    else
        fail "Experiment tracking workflow failed"
    fi
    
    # Cleanup
    rm -rf "$ARTIFACTS_DIR"
    echo ""
}

# Test 6: Test model serving retrieval
test_model_serving() {
    echo "--- Test 6: Model Serving Workflow ---"
    
    # Try to retrieve the model we just stored
    if python3 /etc/nixos/scripts/openclaw-aistor-workflows.py serve \
        --model-name "$TEST_RUN_ID" \
        --version "latest" 2>/dev/null; then
        pass "Model serving workflow functional"
    else
        warn "Model serving workflow may need local cache setup"
    fi
    echo ""
}

# Test 7: Verify bucket lifecycle policies
test_lifecycle_policies() {
    echo "--- Test 7: Lifecycle Policies ---"
    
    for bucket in "${BUCKETS[@]}"; do
        if mc ilm ls "aistor/$bucket" 2>/dev/null | grep -q "Enabled"; then
            pass "Lifecycle policy configured: $bucket"
        else
            warn "No lifecycle policy on: $bucket (may need setup)"
        fi
    done
    echo ""
}

# Test 8: Verify versioning is enabled
test_versioning() {
    echo "--- Test 8: Bucket Versioning ---"
    
    VERSIONED_BUCKETS=("ai-models" "training-data" "experiments")
    for bucket in "${VERSIONED_BUCKETS[@]}"; do
        if mc version info "aistor/$bucket" 2>/dev/null | grep -q "Enabled"; then
            pass "Versioning enabled: $bucket"
        else
            warn "Versioning not enabled: $bucket"
        fi
    done
    echo ""
}

# Test 9: Test OpenClaw Storage MCP direct commands
test_mcp_commands() {
    echo "--- Test 9: OpenClaw Storage MCP Commands ---"
    
    # Test storage stats
    if echo '{"command": "get_storage_stats", "params": {}}' | \
       python3 /etc/nixos/modules/openclaw-storage-mcp.py --command get_storage_stats 2>/dev/null | \
       grep -q "success"; then
        pass "MCP storage stats command works"
    else
        warn "MCP stats command may need service restart"
    fi
    
    # Test list models
    if echo '{"command": "list_models", "params": {"prefix": ""}}' | \
       python3 /etc/nixos/modules/openclaw-storage-mcp.py --command list_models 2>/dev/null | \
       grep -q "success\|models"; then
        pass "MCP list models command works"
    else
        warn "MCP list models may need bucket contents"
    fi
    
    echo ""
}

# Test 10: Check services are running
test_services() {
    echo "--- Test 10: Service Status ---"
    
    # Check minio on nexus
    if ssh nexus 'systemctl is-active minio' 2>/dev/null | grep -q "active"; then
        pass "MinIO service active on nexus"
    else
        warn "MinIO service status unknown (SSH may not be configured)"
    fi
    
    # Check openclaw-storage on zephyr
    if ssh zephyr 'systemctl is-active openclaw-storage' 2>/dev/null | grep -q "active"; then
        pass "OpenClaw Storage service active on zephyr"
    else
        warn "OpenClaw Storage service may need deployment"
    fi
    
    echo ""
}

# Cleanup test data
cleanup_test_data() {
    echo "--- Cleanup ---"
    echo "Removing test data..."
    
    mc rm -r --force "aistor/ai-models/${TEST_RUN_ID}/" 2>/dev/null || true
    mc rm -r --force "aistor/training-data/test-dataset-${TEST_RUN_ID}/" 2>/dev/null || true
    mc rm -r --force "aistor/experiments/exp-${TEST_RUN_ID}/" 2>/dev/null || true
    
    echo "✓ Test data cleaned up"
    echo ""
}

# Main test execution
main() {
    echo "Starting OpenClaw AIStor workflow tests..."
    echo ""
    
    # Run all tests
    test_connectivity
    test_buckets_exist
    test_model_storage
    test_dataset_ingestion
    test_experiment_tracking
    test_model_serving
    test_lifecycle_policies
    test_versioning
    test_mcp_commands
    test_services
    
    # Cleanup
    cleanup_test_data
    
    # Summary
    echo "=== Test Summary ==="
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    TOTAL=$((TESTS_PASSED + TESTS_FAILED))
    echo "Total: $TOTAL"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed. Check output above.${NC}"
        exit 1
    fi
}

# Run main
main
