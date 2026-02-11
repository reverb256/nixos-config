#!/usr/bin/env bash
# OpenClaw CLI Wrapper
# Runs OpenClaw commands inside the container from the host
#
# Usage:
#   openclaw <command> [args...]
#   openclaw gateway --help
#   openclaw status
#   openclaw shell  # Get a shell inside the container
#
# Container must be running: systemctl start openclaw-gateway

set -euo pipefail

CONTAINER_NAME="${OPENCLAW_CONTAINER:-openclaw-gateway}"
PODMAN="${PODMAN:-podman}"

# Check if container is running
check_container() {
  if ! "$PODMAN" ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Error: Container '$CONTAINER_NAME' is not running"
    echo "Start it with: systemctl start openclaw-gateway"
    exit 1
  fi
}

# Get a shell inside the container
shell() {
  check_container
  echo "Entering OpenClaw container shell..."
  "$PODMAN" exec -it "$CONTAINER_NAME" /bin/bash || "$PODMAN" exec -it "$CONTAINER_NAME" /bin/sh
}

# Run OpenClaw CLI command
run_cli() {
  check_container
  "$PODMAN" exec -it "$CONTAINER_NAME" openclaw "$@"
}

# Run non-interactive command (no TTY)
run_cli_no_tty() {
  check_container
  "$PODMAN" exec "$CONTAINER_NAME" openclaw "$@"
}

# Show container logs
logs() {
  "$PODMAN" logs -f "$CONTAINER_NAME"
}

# Show container status
status() {
  echo "=== Container Status ==="
  "$PODMAN" ps -a --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo
  echo "=== Systemd Status ==="
  systemctl status openclaw-gateway --no-pager 2>/dev/null || true
}

# Restart container
restart() {
  echo "Restarting OpenClaw container..."
  sudo systemctl restart openclaw-gateway
  sleep 3
  status
}

# Main
case "${1:-}" in
  shell|sh)
    shell
    ;;
  logs)
    logs
    ;;
  status)
    status
    ;;
  restart)
    restart
    ;;
  exec)
    # Run arbitrary command in container
    shift
    check_container
    "$PODMAN" exec -it "$CONTAINER_NAME" "$@"
    ;;
  --help|-h|help)
    cat << 'EOF'
OpenClaw CLI Wrapper - Run OpenClaw commands inside the container

Usage:
  openclaw <command> [args...]   Run OpenClaw CLI command
  openclaw shell                  Get a bash shell inside the container
  openclaw logs                   Show container logs (follow mode)
  openclaw status                 Show container and systemd status
  openclaw restart                Restart the container
  openclaw exec <cmd> [args...]   Run arbitrary command in container

Examples:
  openclaw gateway --help         Show gateway help
  openclaw status --all           Show full status
  openclaw security audit         Run security audit
  openclaw onboard                Run onboarding wizard
  openclaw doctor                 Run diagnostics
  openclaw shell                  Interactive shell in container

Environment Variables:
  OPENCLAW_CONTAINER  Container name (default: openclaw-gateway)
  PODMAN              Podman binary path (default: podman)

EOF
    ;;
  *)
    # Pass through to OpenClaw CLI
    if [ $# -eq 0 ]; then
      run_cli --help
    else
      run_cli "$@"
    fi
    ;;
esac
