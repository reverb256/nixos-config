#!/usr/bin/env bash
# Visual helpers for elegant justfile output
_header() { printf "\033[1;36m▸\033[0m \033[1m%s\033[0m\n" "$1"; }
_step()   { printf "  \033[2;36m◦\033[0m %s\n" "$1"; }
_done()   { printf "  \033[2;32m✓\033[0m %s\n" "$1"; }
_info()   { printf "  \033[2;90m│\033[0m %s\n" "$1"; }
_time()   { printf "\033[2;90m[%s]\033[0m " "$(date +%H:%M:%S)"; }
_error()  { printf "  \033[2;31m✗\033[0m %s\n" "$1"; }
_warn()   { printf "  \033[2;33m⚠\033[0m %s\n" "$1"; }

# ============================================================================
# MINING PAUSE/RESUME (XMRig API)
# ============================================================================

# Pause XMRig mining during builds
# Uses XMRig HTTP API on localhost:18088, falls back to SIGSTOP
_mining_pause() {
    local XMRIG_API="http://127.0.0.1:18088"
    local TIMEOUT=2

    # Check if xmrig is running
    if ! pgrep -x xmrig >/dev/null 2>&1; then
        return 0  # Not running, nothing to pause
    fi

    # Try API first (throttle to 0% = pause)
    if command -v curl >/dev/null 2>&1; then
        if curl -s --max-time "$TIMEOUT" "$XMRIG_API/throttle" \
            -X PUT \
            -H "Content-Type: application/json" \
            -d '{"throttle": 0}' >/dev/null 2>&1; then
            _info "XMRig paused via API"
            return 0
        fi
    fi

    # Fallback: SIGSTOP
    if pkill -STOP xmrig 2>/dev/null; then
        _warn "XMRig paused via SIGSTOP (API unavailable)"
    fi
}

# Resume XMRig mining after builds
# Uses XMRig HTTP API, falls back to SIGCONT
_mining_resume() {
    local XMRIG_API="http://127.0.0.1:18088"
    local TIMEOUT=2

    # Check if xmrig is running
    if ! pgrep -x xmrig >/dev/null 2>&1; then
        return 0  # Not running, nothing to resume
    fi

    # Try API first (resume to 50% throttle for background operation)
    if command -v curl >/dev/null 2>&1; then
        if curl -s --max-time "$TIMEOUT" "$XMRIG_API/throttle" \
            -X PUT \
            -H "Content-Type: application/json" \
            -d '{"throttle": 50}' >/dev/null 2>&1; then
            _info "XMRig resumed to 50% throttle"
            return 0
        fi
    fi

    # Fallback: SIGCONT
    if pkill -CONT xmrig 2>/dev/null; then
        _warn "XMRig resumed via SIGCONT (API unavailable)"
    fi
}

# Run command with mining pause/resume wrapper
_with_mining_pause() {
    _mining_pause
    "$@"
    local exit_code=$?
    _mining_resume
    return $exit_code
}

# Check for existing nix builds - prevents concurrent build issues
# Returns 0 if safe to build, 1 if build already running
_check_build_lock() {
    local lock_file="/tmp/nixos-build.lock"
    local pid_file="/tmp/nixos-build.pid"

    # Check PID file first
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            local elapsed=$(( $(date +%s) - $(stat -c %Y "$pid_file" 2>/dev/null || echo "0") ))
            local mins=$((elapsed / 60))
            local secs=$((elapsed % 60))
            _error "Build already running!"
            _info "PID: $pid, started ${mins}m ${secs}s ago"
            _info "To monitor: tail -f /tmp/nixos-build.log"
            _info "To kill: kill $pid"
            return 1
        else
            # Stale PID file
            rm -f "$pid_file" "$lock_file" 2>/dev/null || true
        fi
    fi

    # Check for nix build processes
    local nix_pids
    nix_pids=$(pgrep -f "nix build.*nixosConfigurations" 2>/dev/null || true)
    if [[ -n "$nix_pids" ]]; then
        local count=$(echo "$nix_pids" | wc -l)
        _error "Found $count existing nix build process(es):"
        echo "$nix_pids" | head -3 | while read -r pid; do
            ps -p "$pid" -o pid,etime,cmd --no-headers 2>/dev/null | sed 's/^/    /'
        done
        return 1
    fi

    # Check for active nix-daemon builds
    local daemon_pids
    daemon_pids=$(pgrep -f "nix-daemon.*build" 2>/dev/null || true)
    if [[ -n "$daemon_pids" ]]; then
        local count=$(echo "$daemon_pids" | wc -l)
        if [[ $count -gt 5 ]]; then
            _warn "Found $count nix-daemon build processes (might be stale)"
            _info "Run 'sudo pkill -9 nix-daemon' to clean up if needed"
        fi
    fi

    return 0
}

# Acquire build lock
_acquire_build_lock() {
    local lock_file="/tmp/nixos-build.lock"
    local pid_file="/tmp/nixos-build.pid"

    if [[ -f "$lock_file" ]]; then
        _error "Lock file exists: $lock_file"
        return 1
    fi

    touch "$lock_file"
    echo $$ > "$pid_file"
    _info "Build lock acquired: $$"
    return 0
}

# Release build lock
_release_build_lock() {
    rm -f "/tmp/nixos-build.lock" "/tmp/nixos-build.pid" 2>/dev/null || true
}

# Kill ALL conflicting build processes - IDEMPOTENT cleanup
# Returns 0 always (safe to call even if nothing to kill)
_kill_conflicting_builds() {
    local killed=0

    # Kill colmena processes
    local colmena_pids
    colmena_pids=$(pgrep -x colmena 2>/dev/null || true)
    if [[ -n "$colmena_pids" ]]; then
        echo "$colmena_pids" | xargs -r kill -9 2>/dev/null || true
        _warn "Killed colmena processes"
        killed=1
    fi

    # Kill nix build processes (by exact name match, not grep)
    local nix_build_pids
    nix_build_pids=$(pgrep -x nix-build 2>/dev/null || true)
    if [[ -n "$nix_build_pids" ]]; then
        echo "$nix_build_pids" | xargs -r kill -9 2>/dev/null || true
        _warn "Killed nix-build processes"
        killed=1
    fi

    # Clear lock files
    rm -f /tmp/nixos-build.lock /tmp/nixos-build.pid /tmp/nixos-build.log 2>/dev/null || true

    # Clear stale temproots (requires sudo for root-owned)
    if [[ -w /nix/var/nix/temproots ]] || sudo -n true 2>/dev/null; then
        sudo rm -rf /nix/var/nix/temproots/* 2>/dev/null || true
    fi

    if [[ $killed -eq 1 ]]; then
        _done "Conflicting builds cleaned up"
    fi

    return 0
}

# Kill conflicting builds on remote host via SSH
# Usage: _kill_remote_builds hostname
_kill_remote_builds() {
    local host="$1"
    ssh "$host" "
        # Kill colmena
        pgrep -x colmena 2>/dev/null | xargs -r kill -9 2>/dev/null || true
        # Kill nix-build
        pgrep -x nix-build 2>/dev/null | xargs -r kill -9 2>/dev/null || true
        # Clear locks
        rm -f /tmp/nixos-build.lock /tmp/nixos-build.pid /tmp/nixos-build.log 2>/dev/null || true
        # Clear temproots
        sudo rm -rf /nix/var/nix/temproots/* 2>/dev/null || true
        echo 'Cleared: $host'
    " 2>/dev/null || true
}
