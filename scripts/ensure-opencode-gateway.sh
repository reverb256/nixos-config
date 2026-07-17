#!/usr/bin/env bash
#
# OpenCode Gateway Reliability Script
#
# Ensures OpenCode always has a working endpoint to the AI Inference Gateway
# by monitoring health, restarting services, and providing fallbacks.

set -euo pipefail

# Configuration
GATEWAY_URL="http://127.0.0.1:8080"
GATEWAY_HEALTH="${GATEWAY_URL}/health"
LM_STUDIO_URL="http://127.0.0.1:1234"
API_KEY_FILE="/run/agenix/lm-studio-api-key"
LOG_FILE="/var/log/ai-inference/opencode-gateway-check.log"
MAX_RETRIES=3
RETRY_DELAY=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Check gateway health
check_gateway_health() {
    log "INFO" "Checking gateway health at ${GATEWAY_HEALTH}"

    local response
    response=$(curl -s --max-time 5 "${GATEWAY_HEALTH}" 2>&1) || {
        log "ERROR" "Gateway is not responding"
        return 1
    }

    local status
    status=$(echo "$response" | jq -r '.status' // "unknown")

    if [[ "$status" == "healthy" ]]; then
        log "INFO" "✓ Gateway is healthy"

        # Check backend health
        local backend_healthy
        backend_healthy=$(echo "$response" | jq -r '.backend.healthy' // "false")

        if [[ "$backend_healthy" == "true" ]]; then
            log "INFO" "✓ Backend (LM Studio) is healthy"
            return 0
        else
            log "WARN" "✗ Backend (LM Studio) is unhealthy but gateway is up"
            return 2
        fi
    else
        log "ERROR" "✗ Gateway health check failed: $response"
        return 1
    fi
}

# Check LM Studio backend directly
check_lm_studio() {
    log "INFO" "Checking LM Studio at ${LM_STUDIO_URL}"

    if [[ ! -f "$API_KEY_FILE" ]]; then
        log "ERROR" "API key file not found: $API_KEY_FILE"
        return 1
    fi

    local api_key
    api_key=$(cat "$API_KEY_FILE")

    local response
    response=$(curl -s --max-time 5 \
        -H "Authorization: Bearer ${api_key}" \
        "${LM_STUDIO_URL}/v1/models" 2>&1) || {
        log "ERROR" "LM Studio is not responding"
        return 1
    }

    local model_count
    model_count=$(echo "$response" | jq -r '.data | length' // "0")

    if [[ "$model_count" -gt 0 ]]; then
        log "INFO" "✓ LM Studio has ${model_count} models loaded"
        return 0
    else
        log "ERROR" "✗ LM Studio has no models loaded"
        return 1
    fi
}

# Restart gateway service
restart_gateway() {
    log "WARN" "Restarting AI Inference Gateway service..."

    if systemctl restart ai-inference-gateway; then
        log "INFO" "Gateway service restarted successfully"

        # Wait for gateway to come up
        local count=0
        while [[ $count -lt 30 ]]; do
            if curl -s --max-time 2 "${GATEWAY_HEALTH}" >/dev/null 2>&1; then
                log "INFO" "Gateway is back online"
                return 0
            fi
            sleep 1
            ((count++))
        done

        log "ERROR" "Gateway failed to come back online after 30 seconds"
        return 1
    else
        log "ERROR" "Failed to restart gateway service"
        return 1
    fi
}

# Check models are available through gateway
check_gateway_models() {
    log "INFO" "Checking models available through gateway"

    local response
    response=$(curl -s --max-time 5 "${GATEWAY_URL}/v1/models" 2>&1) || {
        log "ERROR" "Failed to fetch models from gateway"
        return 1
    }

    local model_count
    model_count=$(echo "$response" | jq -r '.data | length' // "0")

    if [[ "$model_count" -lt 10 ]]; then
        log "WARN" "Only ${model_count} models available through gateway (expected 20+)"
        return 1
    else
        log "INFO" "✓ ${model_count} models available through gateway"

        # Check for critical models
        local critical_models=(
            "magnum-opus-35b-a3b-i1"
            "qwen/qwen3.5-9b"
        )

        for model in "${critical_models[@]}"; do
            if echo "$response" | jq -r '.data[].id' | grep -q "$model"; then
                log "INFO" "✓ Critical model available: ${model}"
            else
                log "WARN" "✗ Critical model missing: ${model}"
            fi
        done

        return 0
    fi
}

# Test actual inference endpoint
test_inference() {
    log "INFO" "Testing inference endpoint with simple request"

    local response
    response=$(curl -s --max-time 30 \
        -H "Content-Type: application/json" \
        -d '{
            "model": "qwen/qwen3.5-9b",
            "messages": [{"role": "user", "content": "Say OK"}],
            "max_tokens": 10
        }' \
        "${GATEWAY_URL}/v1/chat/completions" 2>&1) || {
        log "ERROR" "Inference test request failed"
        return 1
    }

    local content
    content=$(echo "$response" | jq -r '.choices[0].message.content' // "null")

    if [[ "$content" != "null" ]] && [[ -n "$content" ]]; then
        log "INFO" "✓ Inference test successful: ${content}"
        return 0
    else
        log "ERROR" "✗ Inference test failed: ${response}"
        return 1
    fi
}

# Main health check function
main_health_check() {
    local exit_code=0

    echo -e "${GREEN}=== OpenCode Gateway Health Check ===${NC}"
    echo

    # 1. Check Gateway Health
    echo -e "${YELLOW}[1/5] Checking Gateway Health...${NC}"
    if check_gateway_health; then
        echo -e "${GREEN}✓ Gateway is healthy${NC}"
    else
        echo -e "${RED}✗ Gateway is unhealthy${NC}"
        exit_code=1
    fi
    echo

    # 2. Check LM Studio Backend
    echo -e "${YELLOW}[2/5] Checking LM Studio Backend...${NC}"
    if check_lm_studio; then
        echo -e "${GREEN}✓ LM Studio is healthy${NC}"
    else
        echo -e "${RED}✗ LM Studio is unhealthy${NC}"
        exit_code=1
    fi
    echo

    # 3. Check Gateway Models
    echo -e "${YELLOW}[3/5] Checking Gateway Models...${NC}"
    if check_gateway_models; then
        echo -e "${GREEN}✓ Gateway models are available${NC}"
    else
        echo -e "${YELLOW}⚠ Gateway model check failed (non-critical)${NC}"
    fi
    echo

    # 4. Test Inference
    echo -e "${YELLOW}[4/5] Testing Inference...${NC}"
    if test_inference; then
        echo -e "${GREEN}✓ Inference is working${NC}"
    else
        echo -e "${RED}✗ Inference test failed${NC}"
        exit_code=1
    fi
    echo

    # 5. Summary
    echo -e "${YELLOW}[5/5] Summary${NC}"
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓ All checks passed - OpenCode should work correctly${NC}"
    else
        echo -e "${RED}✗ Some checks failed - OpenCode may have issues${NC}"
        echo
        echo "Troubleshooting steps:"
        echo "1. Check LM Studio is running: systemctl status --user lm-studio"
        echo "2. Check API key exists: ls -la $API_KEY_FILE"
        echo "3. Restart gateway: systemctl restart ai-inference-gateway"
        echo "4. Check logs: journalctl -u ai-inference-gateway -f"
    fi
    echo

    return $exit_code
}

# Auto-repair mode (called from cron/systemd)
auto_repair() {
    log "INFO" "Running auto-repair check"

    if ! check_gateway_health; then
        log "WARN" "Gateway unhealthy, attempting restart"
        restart_gateway
        return $?
    fi

    if ! check_lm_studio; then
        log "WARN" "LM Studio unhealthy - may need manual intervention"
        return 1
    fi

    return 0
}

# Main script logic
case "${1:-check}" in
    check)
        main_health_check
        ;;
    repair)
        auto_repair
        ;;
    watch)
        echo "Watching gateway health (Ctrl+C to stop)..."
        while true; do
            if ! main_health_check >/dev/null 2>&1; then
                log "WARN" "Health check failed, attempting repair"
                auto_repair
            fi
            sleep 60
        done
        ;;
    *)
        echo "Usage: $0 {check|repair|watch}"
        echo
        echo "Commands:"
        echo "  check   - Run health checks and report status"
        echo "  repair  - Attempt to repair issues automatically"
        echo "  watch   - Continuously monitor and auto-repair"
        exit 1
        ;;
esac
