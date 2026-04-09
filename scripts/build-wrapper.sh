#!/usr/bin/env bash
# Idempotent NixOS build wrapper with proper locking and monitoring
# Prevents multiple concurrent builds and provides real-time feedback

set -euo pipefail

# Configuration
LOCK_FILE="/tmp/nixos-build.lock"
LOG_FILE="/tmp/nixos-build.log"
PID_FILE="/tmp/nixos-build.pid"
MAX_BUILD_TIME=3600  # 1 hour max

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

# Check for existing build
check_existing_build() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            local elapsed=$(( $(date +%s) - $(stat -c %Y "$PID_FILE" 2>/dev/null || echo "0") ))
            error "Build already running (PID: $pid, started ${elapsed}s ago)"
            echo ""
            echo "To monitor: tail -f $LOG_FILE"
            echo "To kill: kill $pid"
            echo ""
            ps -p "$pid" -o pid,ppid,cmd --no-headers 2>/dev/null || true
            return 1
        else
            warning "Stale PID file found, cleaning up"
            rm -f "$PID_FILE" "$LOCK_FILE"
        fi
    fi

    # Check for nix build processes
    local nix_builds
    nix_builds=$(pgrep -f "nix build.*nixosConfigurations" | wc -l)
    if [[ $nix_builds -gt 0 ]]; then
        error "Found $nix_builds existing nix build process(es):"
        pgrep -fa "nix build.*nixosConfigurations" | head -5
        return 1
    fi

    # Check for nix-daemon processes doing builds
    local building_daemons
    building_daemons=$(pgrep -f "nix-daemon.*build" | wc -l || echo "0")
    if [[ $building_daemons -gt 0 ]]; then
        warning "Found $building_daemons nix-daemon build process(es)"
        pgrep -fa "nix-daemon.*build" | head -3 || true
    fi

    return 0
}

# Acquire lock
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        error "Lock file exists: $LOCK_FILE"
        return 1
    fi
    touch "$LOCK_FILE"
    echo $$ > "$PID_FILE"
    info "Lock acquired: $$"
}

# Release lock
release_lock() {
    rm -f "$LOCK_FILE" "$PID_FILE"
    info "Lock released"
}

# Monitor build progress
monitor_build() {
    local build_pid=$1
    local start_time=$(date +%s)

    info "Build started (PID: $build_pid)"
    info "Log file: $LOG_FILE"
    echo ""

    # Initial wait
    sleep 5

    # Monitor loop
    while kill -0 "$build_pid" 2>/dev/null; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Check for timeout
        if [[ $elapsed -gt $MAX_BUILD_TIME ]]; then
            error "Build timeout (${elapsed}s), killing..."
            kill -9 "$build_pid" 2>/dev/null || true
            return 1
        fi

        # Show progress
        local minutes=$((elapsed / 60))
        local seconds=$((elapsed % 60))
        info "Building... (${minutes}m ${seconds}s elapsed) [PID: $build_pid]"

        # Check if process is stuck (not using CPU)
        local cpu_usage=$(ps -p "$build_pid" -o %cpu= 2>/dev/null || echo "0")
        if (( $(echo "$cpu_usage < 0.1" | bc -l) )); then
            # Check if it's waiting on I/O or locks
            local state=$(ps -p "$build_pid" -o state= 2>/dev/null || echo "?")
            if [[ "$state" == "D" ]]; then
                warning "Process in uninterruptible sleep (I/O wait)"
            fi
        fi

        sleep 30
    done

    # Get exit code
    wait "$build_pid"
    local exit_code=$?

    local total_elapsed=$(($(date +%s) - start_time))
    local total_minutes=$((total_elapsed / 60))
    local total_seconds=$((total_elapsed % 60))

    if [[ $exit_code -eq 0 ]]; then
        success "Build completed in ${total_minutes}m ${total_seconds}s!"
    else
        error "Build failed with exit code $exit_code (after ${total_minutes}m ${total_seconds}s)"
    fi

    return $exit_code
}

# Main build function
do_build() {
    local target=${1:-""}
    local host=${2:-"$(hostname)"}

    if [[ -z "$target" ]]; then
        error "Usage: $0 <nixos-target> [host]"
        error "Example: $0 nixosConfigurations.zephyr.config.system.build.toplevel zephyr"
        return 1
    fi

    info "Building: $target (host: $host)"

    # Run the actual build
    if [[ "$host" == "$(hostname)" ]]; then
        # Local build
        nix build ".#$target" 2>&1 | tee -a "$LOG_FILE"
    else
        # Remote build via SSH
        ssh "$host" "cd /etc/nixos && nix build '.#$target'" 2>&1 | tee -a "$LOG_FILE"
    fi
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    release_lock
    if [[ $exit_code -ne 0 ]]; then
        error "Build exited with code $exit_code"
    fi
}

# Main
main() {
    local target=$1

    # Check existing builds first
    if ! check_existing_build; then
        exit 1
    fi

    # Acquire lock
    acquire_lock || exit 1

    # Set up cleanup trap
    trap cleanup EXIT INT TERM

    # Start build in background and monitor
    local build_pid
    do_build "$target" &
    build_pid=$!

    # Monitor the build
    monitor_build "$build_pid"
    exit $?
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
