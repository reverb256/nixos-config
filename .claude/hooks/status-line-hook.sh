#!/bin/bash
# Status Line Hook for MCP Integration
# This hook updates the status line with tool availability

set -e

# Configuration
MCP_SERVER_URL="http://localhost:3000"
STATUS_FILE="/tmp/claude-status.txt"

# Check MCP server status
check_mcp_server() {
  if curl -s --connect-timeout 2 "$MCP_SERVER_URL/health" > /dev/null 2>&1; then
    echo "MCP:✓"
  else
    echo "MCP:✗"
  fi
}

# Check web search availability
check_web_search() {
  if curl -s --connect-timeout 2 "$MCP_SERVER_URL/health" > /dev/null 2>&1; then
    echo "WebSearch:✓"
  else
    echo "WebSearch:✗"
  fi
}

# Generate status line
generate_status() {
  MCP_STATUS=$(check_mcp_server)
  WEB_SEARCH_STATUS=$(check_web_search)

  STATUS_LINE="[$MCP_STATUS $WEB_SEARCH_STATUS]"

  # Write to status file
  echo "$STATUS_LINE" > "$STATUS_FILE"

  # Output status line
  echo "$STATUS_LINE"
}

# Handle different status line modes
case "${1:-status}" in
  "status")
    generate_status
    ;;
  "mcp")
    check_mcp_server
    ;;
  "web-search")
    check_web_search
    ;;
  "clear")
    echo "" > "$STATUS_FILE"
    ;;
  *)
    echo "Usage: $0 [status|mcp|web-search|clear]"
    exit 1
    ;;
esac