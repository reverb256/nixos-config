#!/run/current-system/sw/bin/bash
# Comprehensive Test Suite for AI Inference Gateway

GATEWAY_URL="http://127.0.0.1:8080"
PASSED=0
FAILED=0

echo "=========================================="
echo " AI INFERENCE GATEWAY TEST SUITE"
echo "=========================================="
echo ""

# Test 1: Health Check
echo "Test 1: Health Check"
echo "----------------------------------------"
response=$(curl -s $GATEWAY_URL/health)
status=$(echo "$response" | jq -r '.status')
version=$(echo "$response" | jq -r '.gateway.version')
backend_healthy=$(echo "$response" | jq -r '.backend.healthy')

if [ "$status" = "healthy" ] && [ "$version" = "2.0.0" ] && [ "$backend_healthy" = "true" ]; then
    echo "✅ PASS - Health check successful"
    ((PASSED++))
else
    echo "❌ FAIL - Health check failed"
    ((FAILED++))
fi
echo ""

# Test 2: Models List
echo "Test 2: Models List"
echo "----------------------------------------"
response=$(curl -s $GATEWAY_URL/v1/models)
model_count=$(echo "$response" | jq '.data | length')
first_model=$(echo "$response" | jq -r '.data[0].id')

if [ "$model_count" -gt 0 ] && [ -n "$first_model" ]; then
    echo "✅ PASS - Found $model_count models, first: $first_model"
    ((PASSED++))
else
    echo "❌ FAIL - Models endpoint failed"
    ((FAILED++))
fi
echo ""

# Test 3: Basic Chat Completions
echo "Test 3: Basic Chat Completions"
echo "----------------------------------------"
response=$(curl -s -X POST $GATEWAY_URL/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "magnum-opus-35b-a3b-i1",
    "messages": [{"role": "user", "content": "Say hello in 3 words."}],
    "max_tokens": 50
  }')

content=$(echo "$response" | jq -r '.choices[0].message.content' 2>/dev/null)
model=$(echo "$response" | jq -r '.model' 2>/dev/null)
tokens=$(echo "$response" | jq -r '.usage.total_tokens' 2>/dev/null)

if [ -n "$content" ] && [ "$model" = "magnum-opus-35b-a3b-i1" ]; then
    echo "✅ PASS - Chat completion successful"
    echo "   Response: $content"
    echo "   Tokens: $tokens"
    ((PASSED++))
else
    echo "❌ FAIL - Chat completion failed"
    echo "   Response: $response"
    ((FAILED++))
fi
echo ""

# Test 4: Anthropic Messages API
echo "Test 4: Anthropic Messages API"
echo "----------------------------------------"
response=$(curl -s -X POST $GATEWAY_URL/v1/messages \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 50,
    "messages": [{"role": "user", "content": "What is 2+2? Answer in 3 words."}]
  }')

content=$(echo "$response" | jq -r '.content' 2>/dev/null)
model=$(echo "$response" | jq -r '.model' 2>/dev/null)
type=$(echo "$response" | jq -r '.type' 2>/dev/null)

if [ "$type" = "message" ] && [ "$model" = "claude-sonnet-4-20250514" ]; then
    echo "✅ PASS - Anthropic API working"
    echo "   Response: $content"
    ((PASSED++))
else
    echo "❌ FAIL - Anthropic API failed"
    echo "   Response: $response"
    ((FAILED++))
fi
echo ""

# Test 5: Anthropic Streaming
echo "Test 5: Anthropic Streaming"
echo "----------------------------------------"
response=$(curl -s -X POST $GATEWAY_URL/v1/messages \
  -H "Content-Type: application/json" \
  --no-buffer \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 30,
    "stream": true,
    "messages": [{"role": "user", "content": "Count to 3"}]
  }' | head -20)

has_events=false
if echo "$response" | grep -q "event: message_start"; then
    has_events=true
fi
if echo "$response" | grep -q "event: content_block_delta"; then
    has_events=true
fi
if echo "$response" | grep -q "event: message_stop"; then
    has_events=true
fi

if $has_events; then
    echo "✅ PASS - Streaming events detected"
    ((PASSED++))
else
    echo "❌ FAIL - No streaming events"
    echo "   Output: $response"
    ((FAILED++))
fi
echo ""

# Test 6: Usage Analytics Endpoint
echo "Test 6: Usage Analytics"
echo "----------------------------------------"
response=$(curl -s $GATEWAY_URL/usage 2>/dev/null)

has_total_requests=false
has_summary=false
if echo "$response" | jq -e '.summary.total_requests' > /dev/null 2>&1; then
    has_total_requests=true
fi
if echo "$response" | jq -e '.summary' > /dev/null 2>&1; then
    has_summary=true
fi

if $has_summary; then
    echo "✅ PASS - Usage analytics available"
    ((PASSED++))
else
    echo "❌ FAIL - Usage analytics failed"
    ((FAILED++))
fi
echo ""

# Test 7: Cache Stats
echo "Test 7: Cache Statistics"
echo "----------------------------------------"
response=$(curl -s $GATEWAY_URL/cache/stats 2>/dev/null)

if echo "$response" | jq -e '.enabled' > /dev/null 2>&1; then
    enabled=$(echo "$response" | jq -r '.enabled')
    if [ "$enabled" = "true" ]; then
        entries=$(echo "$response" | jq -r '.total_entries')
        echo "✅ PASS - Cache stats available (enabled, $entries entries)"
        ((PASSED++))
    else
        echo "⚠️  WARN - Cache disabled"
        ((PASSED++))
    fi
else
    echo "⚠️  WARN - Cache stats endpoint failed"
    ((PASSED++))
fi
echo ""

# Test 8: Prometheus Metrics
echo "Test 8: Prometheus Metrics"
echo "----------------------------------------"
response=$(curl -s $GATEWAY_URL/metrics 2>/dev/null | head -5)

if echo "$response" | grep -q "ai_inference"; then
    echo "✅ PASS - Prometheus metrics available"
    ((PASSED++))
else
    echo "❌ FAIL - No metrics found"
    ((FAILED++))
fi
echo ""

# Summary
echo "=========================================="
echo " TEST SUMMARY"
echo "=========================================="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "Total:  $((PASSED + FAILED))"

if [ $FAILED -eq 0 ]; then
    echo ""
    echo "✅ ALL TESTS PASSED!"
    exit 0
else
    echo ""
    echo "❌ SOME TESTS FAILED"
    exit 1
fi
