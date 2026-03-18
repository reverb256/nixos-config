#!/usr/bin/env bash
#
# SearXNG Default Search Configuration
# Makes SearXNG the primary search provider for the cluster
#

set -euo pipefail

GATEWAY_URL="http://127.0.0.1:8080"
SEARXNG_URL="http://127.0.0.1:7777"

echo "=== SearXNG Default Search Setup ==="
echo ""

# 1. Test SearXNG directly
echo "1. Testing SearXNG direct access..."
if curl -s "${SEARXNG_URL}/search?q=test&format=json" | jq -e '.results | length' > /dev/null 2>&1; then
    echo "   ✅ SearXNG is responding"
else
    echo "   ❌ SearXNG is not responding"
    exit 1
fi

# 2. Test Gateway SearXNG integration
echo ""
echo "2. Testing Gateway SearXNG integration..."
if curl -s -X POST "${GATEWAY_URL}/mcp/call" \
    -H "Content-Type: application/json" \
    -d '{"server":"searxng","tool":"web_search","arguments":{"query":"test","max_results":1}}' \
    | jq -e '.result' > /dev/null 2>&1; then
    echo "   ✅ Gateway SearXNG integration working"
else
    echo "   ❌ Gateway SearXNG integration failed"
    exit 1
fi

# 3. Check SearXNG server health
echo ""
echo "3. Checking SearXNG server status..."
SERVER_STATUS=$(curl -s "${GATEWAY_URL}/mcp/servers" | jq -r '.servers[] | select(.name == "searxng") | .healthy')
if [ "$SERVER_STATUS" = "true" ]; then
    echo "   ✅ SearXNG server is healthy"
else
    echo "   ❌ SearXNG server is unhealthy"
    exit 1
fi

# 4. List available SearXNG tools
echo ""
echo "4. Available SearXNG tools:"
curl -s "${GATEWAY_URL}/mcp/tools" | \
    jq -r '.tools[] | select(.server == "searxng") | "   - \(.name): \(.description)"' | \
    head -10

echo ""
echo "=== SearXNG is ready as default search ==="
echo ""
echo "Usage examples:"
echo "  # Web search"
echo '  curl -X POST "${GATEWAY_URL}/mcp/call" \'
echo '    -H "Content-Type: application/json" \'
echo '    -d '"'"'{"server":"searxng","tool":"web_search","arguments":{"query":"NixOS config"}}'"'"''
echo ""
echo "  # GitHub search"
echo '  curl -X POST "${GATEWAY_URL}/mcp/call" \'
echo '    -H "Content-Type: application/json" \'
echo '    -d '"'"'{"server":"searxng","tool":"search_github","arguments":{"query":"kubernetes operator"}}'"'"''
echo ""
echo "  # NixOS options search"
echo '  curl -X POST "${GATEWAY_URL}/mcp/call" \'
echo '    -H "Content-Type: application/json" \'
echo '    -d '"'"'{"server":"searxng","tool":"search_nixos_options","arguments":{"query":"networking firewall"}}'"'"'
