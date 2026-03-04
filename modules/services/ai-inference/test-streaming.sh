#!/run/current-system/sw/bin/bash
# Test script for Anthropic Messages API streaming support

GATEWAY_URL="http://127.0.0.1:8080"
TEST_PASSED=0
TEST_FAILED=0

echo "======================================"
echo "Anthropic Streaming API Tests"
echo "======================================"
echo ""

# Test 1: Basic streaming request
echo "Test 1: Basic streaming request"
echo "---------------------------------------"
response=$(curl -s -X POST $GATEWAY_URL/v1/messages \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  --no-buffer \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 100,
    "stream": true,
    "messages": [
      {"role": "user", "content": "Say hello in exactly 5 words"}
    ]
  }')

echo "$response" | head -30

# Check for proper SSE events
if echo "$response" | grep -q "event: message_start"; then
    echo "✓ message_start event found"
    ((TEST_PASSED++))
else
    echo "✗ message_start event missing"
    ((TEST_FAILED++))
fi

if echo "$response" | grep -q "event: content_block_start"; then
    echo "✓ content_block_start event found"
    ((TEST_PASSED++))
else
    echo "✗ content_block_start event missing"
    ((TEST_FAILED++))
fi

if echo "$response" | grep -q "event: content_block_delta"; then
    echo "✓ content_block_delta events found"
    ((TEST_PASSED++))
else
    echo "✗ content_block_delta events missing"
    ((TEST_FAILED++))
fi

if echo "$response" | grep -q "event: content_block_stop"; then
    echo "✓ content_block_stop event found"
    ((TEST_PASSED++))
else
    echo "✗ content_block_stop event missing"
    ((TEST_FAILED++))
fi

if echo "$response" | grep -q "event: message_delta"; then
    echo "✓ message_delta event found"
    ((TEST_PASSED++))
else
    echo "✗ message_delta event missing"
    ((TEST_FAILED++))
fi

if echo "$response" | grep -q "event: message_stop"; then
    echo "✓ message_stop event found"
    ((TEST_PASSED++))
else
    echo "✗ message_stop event missing"
    ((TEST_FAILED++))
fi

echo ""
echo "======================================"
echo "Test Summary: $TEST_PASSED passed, $TEST_FAILED failed"
echo "======================================"
