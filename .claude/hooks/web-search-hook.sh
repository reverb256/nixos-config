#!/bin/bash
# Web Search Hook for MCP Integration
# This hook is called by Claude Code when web search is requested

set -e

# Configuration
MCP_SERVER_URL="http://localhost:3000"
TIMEOUT=10000
MAX_RESULTS=10

# Log hook execution
echo "Web search hook executed with args: $@" >&2

# Check if MCP server is running
if ! curl -s --connect-timeout 2 "http://localhost:3000/health" > /dev/null; then
  echo "Error: MCP server is not running on localhost:3000" >&2
  echo "Please ensure the MCP server is started: systemctl start mcp-server" >&2
  exit 1
fi

# Parse query from arguments
QUERY=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -q|--query)
      QUERY="$2"
      shift 2
      ;;
    --query=*)
      QUERY="${1#*=}"
      shift
      ;;
    *)
      if [[ -z "$QUERY" ]]; then
        QUERY="$1"
      fi
      shift
      ;;
  esac
done

# Validate query
if [[ -z "$QUERY" ]]; then
  echo "Usage: $0 [-q|--query] <search query>" >&2
  exit 1
fi

# Prepare search request
SEARCH_DATA=$(cat <<EOF
{
  "query": "$QUERY",
  "maxResults": $MAX_RESULTS,
  "timeout": $TIMEOUT
}
EOF
)

# Perform web search via MCP server
echo "Searching for: $QUERY" >&2
RESPONSE=$(curl -s -X POST "$MCP_SERVER_URL/search" \
  -H "Content-Type: application/json" \
  -d "$SEARCH_DATA" \
  --connect-timeout 5 \
  --max-time 30)

# Check if search was successful
if [[ $? -ne 0 ]]; then
  echo "Error: Failed to perform web search" >&2
  exit 1
fi

# Parse and display results
if echo "$RESPONSE" | jq -e '.results' > /dev/null 2>&1; then
  echo "Web search completed successfully" >&2
  echo "$RESPONSE" | jq -r '.results[] | "Title: \(.title)\nURL: \(.url)\nSnippet: \(.snippet)\n---"'
else
  echo "Error: Invalid response from MCP server" >&2
  echo "Response: $RESPONSE" >&2
  exit 1
fi