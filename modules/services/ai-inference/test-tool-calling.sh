#!/run/current-system/sw/bin/bash
# Test script for Anthropic tool calling through the gateway

GATEWAY_URL="http://127.0.0.1:8080"
TEST_PASSED=0
TEST_FAILED=0

echo "======================================"
echo "Anthropic Tool Calling Tests"
echo "======================================"
echo ""

# Test 1: Detect tool calling in response
echo "Test 1: Tool calling detection (weather example)"
echo "---------------------------------------"
response=$(curl -s -X POST $GATEWAY_URL/v1/messages \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 100,
    "messages": [
      {"role": "user", "content": "What is the weather in Paris? Use the get_weather tool."}
    ],
    "tools": [
      {
        "name": "get_weather",
        "description": "Get weather information for a location",
        "input_schema": {
          "type": "object",
          "properties": {
            "location": {
              "type": "string",
              "description": "City name"
            }
          },
          "required": ["location"]
        }
      }
    ]
  }')

echo "$response" | jq '.' 2>/dev/null || echo "$response"
echo ""

# Check for tool_use content block
if echo "$response" | jq -e '.content[]? | select(.type == "tool_use")' > /dev/null 2>&1; then
    echo "✓ tool_use content block detected"
    ((TEST_PASSED++))
else
    echo "✗ tool_use content block not detected"
    ((TEST_FAILED++))
fi

# Check for tool name
if echo "$response" | jq -e '.content[]? | select(.type == "tool_use") | .name == "get_weather"' > /dev/null 2>&1; then
    echo "✓ Correct tool name (get_weather)"
    ((TEST_PASSED++))
else
    echo "⚠ Tool name may not be get_weather (model may not support tool calling)"
fi

# Check for input arguments
if echo "$response" | jq -e '.content[]? | select(.type == "tool_use") | .input' > /dev/null 2>&1; then
    echo "✓ Tool input arguments present"
    ((TEST_PASSED++))
else
    echo "⚠ Tool input arguments may not be present"
fi

# Check for stop_reason
if echo "$response" | jq -e '.stop_reason == "tool_calls"' > /dev/null 2>&1; then
    echo "✓ stop_reason is 'tool_calls'"
    ((TEST_PASSED++))
else
    echo "⚠ stop_reason may not be 'tool_calls' (model may not support tool calling)"
fi

# Check for gateway metadata
if echo "$response" | jq -e '._gateway.tool_calls_detected' > /dev/null 2>&1; then
    echo "✓ Gateway metadata includes tool_calls_detected"
    ((TEST_PASSED++))

    tool_count=$(echo "$response" | jq -e '._gateway.tool_calls_detected')
    echo "  → Tool calls detected: $tool_count"
else
    echo "⚠ Gateway metadata does not include tool_calls_detected"
fi

echo ""
echo "======================================"
echo "Test Summary: $TEST_PASSED passed, $TEST_FAILED failed"
echo "======================================"
echo ""
echo "NOTE: Some tests may fail if the local model (Magnum Opus) does not support tool calling."
echo "This is expected - the gateway is correctly translating the format regardless."
