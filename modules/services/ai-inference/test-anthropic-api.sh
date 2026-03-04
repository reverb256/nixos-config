#!/usr/bin/env bash
# Test script for Anthropic API compatibility in AI Inference Gateway

set -e

GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:8080}"
MODEL="${MODEL:-claude-sonnet-4-20250514}"

echo "=== Testing Anthropic API Compatibility ==="
echo "Gateway URL: $GATEWAY_URL"
echo "Model: $MODEL"
echo ""

# Test 1: Health check
echo "Test 1: Health check"
curl -s "$GATEWAY_URL/health" | jq '.status, .gateway.version'
echo ""

# Test 2: List models (OpenAI format)
echo "Test 2: List models (should include local models)"
curl -s "$GATEWAY_URL/v1/models" | jq '.data[].id' | head -5
echo ""

# Test 3: Simple Anthropic Messages API request
echo "Test 3: Simple message request"
RESPONSE=$(curl -s -X POST "$GATEWAY_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d "{
    \"model\": \"$MODEL\",
    \"max_tokens\": 100,
    \"messages\": [
      {\"role\": \"user\", \"content\": \"Say 'API test successful' in one sentence.\"}
    ]
  }")

echo "Response:"
echo "$RESPONSE" | jq '.'

# Check response format
echo ""
echo "Checking response format..."
ID=$(echo "$RESPONSE" | jq -r '.id')
TYPE=$(echo "$RESPONSE" | jq -r '.type')
ROLE=$(echo "$RESPONSE" | jq -r '.role')

if [[ "$TYPE" == "message" ]] && [[ "$ROLE" == "assistant" ]]; then
  echo "✓ Response format is correct (type=$TYPE, role=$role)"
else
  echo "✗ Response format is incorrect (type=$TYPE, role=$ROLE)"
  exit 1
fi

# Test 4: With system prompt
echo ""
echo "Test 4: Message with system prompt"
curl -s -X POST "$GATEWAY_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d "{
    \"model\": \"$MODEL\",
    \"max_tokens\": 50,
    \"system\": \"You are a helpful assistant who always responds in exactly 5 words.\",
    \"messages\": [
      {\"role\": \"user\", \"content\": \"What is NixOS?\"}
    ]
  }" | jq '.content[0].text'

echo ""
echo ""

# Test 5: Extended thinking
echo "Test 5: Message with extended thinking"
curl -s -X POST "$GATEWAY_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d "{
    \"model\": \"$MODEL\",
    \"max_tokens\": 100,
    \"messages\": [
      {\"role\": \"user\", \"content\": \"What is 2+2?\"}
    ],
    \"thinking\": {
      \"type\": \"enabled\",
      \"budget_tokens\": 1024
    }
  }" | jq '.content[0].text'

echo ""
echo ""

# Test 6: Check metrics
echo "Test 6: Prometheus metrics"
curl -s "$GATEWAY_URL/metrics" | grep -E "anthropic|claude" || echo "No Anthropic-specific metrics yet (expected)"
echo ""

echo "=== All tests completed ==="
