#!/bin/bash
# Claude Code CLI Wrapper for Kubernetes
# Usage: ./claude-kubectl.sh "your prompt here"

set -e

NAMESPACE="ai-inference"
SELECTOR="app=claude-code"

# Find least busy pod (fewest active conversations)
POD=$(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | \
  while read pod; do
    # Get active conversations from metrics
    ACTIVE=$(kubectl exec -n "$NAMESPACE" "$pod" -- curl -s localhost:9090/metrics | \
      grep claude_active_conversations | awk '{print $2}' || echo "0")
    echo "$ACTIVE $pod"
  done | sort -n | head -1 | awk '{print $2}')

if [ -z "$POD" ]; then
  echo "❌ No Claude pods found in namespace $NAMESPACE"
  exit 1
fi

echo "🤖 Connecting to Claude pod: $POD"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Forward Claude API port to localhost
echo "📡 Setting up port forward..."
kubectl port-forward -n "$NAMESPACE" "$POD" 8080:8080 > /dev/null 2>&1 &
PF_PID=$!

# Wait for port-forward to be ready
sleep 2

# Trap to cleanup port-forward on exit
trap "kill $PF_PID 2>/dev/null || true" EXIT

# Use Claude API
if [ $# -eq 0 ]; then
  # Interactive mode
  echo "🔄 Entering interactive mode (Ctrl+D to exit)"
  echo ""
  kubectl exec -it -n "$NAMESPACE" "$POD" -- /bin/bash
else
  # Direct prompt mode
  PROMPT="$*"
  echo "💬 Prompt: $PROMPT"
  echo ""

  # Send request to Claude API
  curl -s http://localhost:8080/v1/messages \
    -H "Content-Type: application/json" \
    -d "{\"prompt\": \"$PROMPT\", \"stream\": true}" | \
    jq -r '.content // .'
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
