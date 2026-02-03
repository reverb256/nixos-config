#!/usr/bin/env bash
# NixOS Manager MCP Server
# Implements Model Context Protocol for NixOS operations

set -e

# Logging function
log() {
    echo "[NIXOS-MANAGER] $*" >&2
}

# Send JSON-RPC response
send_response() {
    local id="$1"
    local result="$2"
    local error="$3"
    
    if [ -n "$error" ]; then
        printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32603,"message":"%s"}}\n' "$id" "$error"
    else
        printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$id" "$result"
    fi
}

# Handle tool calls
handle_tool_call() {
    local method="$1"
    local params="$2"
    local id="$3"
    
    case "$method" in
        "rebuild_system")
            local flake=$(echo "$params" | jq -r '.flake // ".#$(hostname)"')
            local operation=$(echo "$params" | jq -r '.operation // "switch"')
            local max_jobs=$(echo "$params" | jq -r '.max_jobs // 2')
            local cores=$(echo "$params" | jq -r '.cores // 2')
            local upgrade=$(echo "$params" | jq -r '.upgrade // false')
            
            local cmd="sudo nixos-rebuild $operation --flake $flake --max-jobs $max_jobs --cores $cores"
            if [ "$upgrade" = "true" ]; then
                cmd="$cmd --upgrade"
            fi
            
            log "Executing: $cmd"
            if output=$($cmd 2>&1); then
                send_response "$id" "{\"success\": true, \"output\": $(echo "$output" | jq -R -s '.')}"
            else
                send_response "$id" "" "Rebuild failed: $output"
            fi
            ;;
            
        "search_packages")
            local query=$(echo "$params" | jq -r '.query')
            local channel=$(echo "$params" | jq -r '.channel // "nixpkgs"')
            
            log "Searching for: $query in $channel"
            if output=$(nix search "$channel" "$query" --json 2>&1); then
                send_response "$id" "$output"
            else
                send_response "$id" "" "Search failed: $output"
            fi
            ;;
            
        "install_shell_packages")
            local packages=$(echo "$params" | jq -r '.packages | join(" ")')
            local command=$(echo "$params" | jq -r '.command // ""')
            local pure=$(echo "$params" | jq -r '.pure // false')
            
            local cmd="nix-shell -p $packages"
            if [ "$pure" = "true" ]; then
                cmd="$cmd --pure"
            fi
            if [ -n "$command" ]; then
                cmd="$cmd --run '$command'"
            fi
            
            log "Executing: $cmd"
            if output=$($cmd 2>&1); then
                send_response "$id" "{\"success\": true, \"output\": $(echo "$output" | jq -R -s '.')}"
            else
                send_response "$id" "" "Shell install failed: $output"
            fi
            ;;
            
        "manage_secrets")
            local operation=$(echo "$params" | jq -r '.operation')
            local file=$(echo "$params" | jq -r '.file // ""')
            local output=$(echo "$params" | jq -r '.output // ""')
            local recipients=$(echo "$params" | jq -r '.recipients // [] | join(" -r ")')
            
            case "$operation" in
                "encrypt")
                    if [ -z "$file" ] || [ -z "$output" ]; then
                        send_response "$id" "" "Missing file or output path"
                        return
                    fi
                    cmd="age -r $recipients -o $output $file"
                    ;;
                "decrypt")
                    if [ -z "$file" ] || [ -z "$output" ]; then
                        send_response "$id" "" "Missing file or output path"
                        return
                    fi
                    cmd="age -d -i ~/.config/sops/age/keys.txt -o $output $file"
                    ;;
                "generate-key")
                    mkdir -p ~/.config/sops/age
                    cmd="age-keygen -o ~/.config/sops/age/keys.txt"
                    ;;
                "rekey")
                    cmd="agenix -r"
                    ;;
                *)
                    send_response "$id" "" "Unknown operation: $operation"
                    return
                    ;;
            esac
            
            log "Executing: $cmd"
            if result=$($cmd 2>&1); then
                send_response "$id" "{\"success\": true, \"output\": $(echo "$result" | jq -R -s '.')}"
            else
                send_response "$id" "" "Secret operation failed: $result"
            fi
            ;;
            
        "collect_garbage")
            local delete_older=$(echo "$params" | jq -r '.delete_older_than // ""')
            local optimise=$(echo "$params" | jq -r '.optimise // false')
            
            local cmd="sudo nix-collect-garbage"
            if [ -n "$delete_older" ]; then
                cmd="$cmd --delete-older-than $delete_older"
            fi
            
            log "Executing: $cmd"
            if output=$($cmd 2>&1); then
                if [ "$optimise" = "true" ]; then
                    sudo nix-store --optimise 2>&1 | log
                fi
                send_response "$id" "{\"success\": true, \"output\": $(echo "$output" | jq -R -s '.')}"
            else
                send_response "$id" "" "Garbage collection failed: $output"
            fi
            ;;
            
        "flake_update")
            local inputs=$(echo "$params" | jq -r '.inputs // [] | join(" ")')
            local commit=$(echo "$params" | jq -r '.commit // true')
            
            local cmd="nix flake update"
            if [ -n "$inputs" ]; then
                for input in $inputs; do
                    cmd="$cmd --update-input $input"
                done
            fi
            
            log "Executing: $cmd"
            if output=$($cmd 2>&1); then
                if [ "$commit" = "true" ]; then
                    git add flake.lock
                    git commit -m "Update flake inputs" 2>&1 | log
                fi
                send_response "$id" "{\"success\": true, \"output\": $(echo "$output" | jq -R -s '.')}"
            else
                send_response "$id" "" "Flake update failed: $output"
            fi
            ;;
            
        "check_health")
            local full=$(echo "$params" | jq -r '.full // false')
            
            log "Checking NixOS health..."
            local health_info="{"
            health_info+="\"store_size\": \"$(du -sh /nix/store | cut -f1)\","
            health_info+="\"generations\": $(nixos-rebuild list-generations --json 2>/dev/null | jq length || echo 0),"
            health_info+="\"disk_usage\": \"$(df -h /nix | tail -1 | awk '{print $5}')\","
            health_info+="\"nix_version\": \"$(nix --version | cut -d' ' -f3)\""
            
            if [ "$full" = "true" ]; then
                health_info+=","
                health_info+="\"store_verify\": \"$(nix-store --verify 2>&1 | head -1)\""
            fi
            
            health_info+="}"
            
            send_response "$id" "$health_info"
            ;;
            
        *)
            send_response "$id" "" "Unknown tool: $method"
            ;;
    esac
}

# Main MCP server loop
main() {
    log "NixOS Manager MCP Server started"
    
    while IFS= read -r line; do
        # Parse JSON-RPC request
        if ! echo "$line" | jq -e . >/dev/null 2>&1; then
            continue
        fi
        
        local jsonrpc=$(echo "$line" | jq -r '.jsonrpc // ""')
        local method=$(echo "$line" | jq -r '.method // ""')
        local params=$(echo "$line" | jq -r '.params // {}')
        local id=$(echo "$line" | jq -r '.id // ""')
        
        # Handle initialization
        if [ "$method" = "initialize" ]; then
            send_response "$id" "{\"protocolVersion\": \"2024-11-05\", \"capabilities\": {}, \"serverInfo\": {\"name\": \"nixos-manager\", \"version\": \"2.0.0\"}}"
            continue
        fi
        
        # Handle tool list request
        if [ "$method" = "tools/list" ]; then
            local tools=$(cat /home/j_kro/.config/opencode/skills/nixos-manager/mcp.json | jq '.tools')
            send_response "$id" "$tools"
            continue
        fi
        
        # Handle tool calls
        if [ "$method" = "tools/call" ]; then
            local tool_name=$(echo "$params" | jq -r '.name')
            local tool_params=$(echo "$params" | jq -r '.arguments // {}')
            handle_tool_call "$tool_name" "$tool_params" "$id"
            continue
        fi
        
        # Ping/pong for keepalive
        if [ "$method" = "ping" ]; then
            send_response "$id" "{}"
            continue
        fi
        
        log "Unknown method: $method"
        send_response "$id" "" "Method not found: $method"
    done
}

# Ensure jq is available
if ! command -v jq &>/dev/null; then
    log "ERROR: jq is required but not installed"
    exit 1
fi

# Run main loop
main
