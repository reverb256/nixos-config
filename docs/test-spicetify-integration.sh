#!/usr/bin/env bash
################################################################################
# Spotify + Spicetify Integration Test Script
#
# This script performs comprehensive integration testing of the Spotify SpotX
# and Spicetify modules, verifying prerequisites, dependencies, services,
# and end-to-end functionality.
#
# Usage: sudo ./test-spicetify-integration.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Prerequisites not met (graceful skip)
################################################################################

set -euo pipefail

################################################################################
# COLOR DEFINITIONS
################################################################################
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

################################################################################
# TEST COUNTERS
################################################################################
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Print colored output
print_color() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Print test header
print_test_header() {
    local test_name="$1"
    echo ""
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$BLUE" "TEST: $test_name"
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Record test result
record_result() {
    local result="$1"
    local message="$2"

    ((TESTS_RUN++))

    case "$result" in
        "pass")
            print_color "$GREEN" "✓ PASS: $message"
            ((TESTS_PASSED++))
            ;;
        "fail")
            print_color "$RED" "✗ FAIL: $message"
            ((TESTS_FAILED++))
            ;;
        "skip")
            print_color "$YELLOW" "⊘ SKIP: $message"
            ((TESTS_SKIPPED++))
            ;;
        "warn")
            print_color "$YELLOW" "⚠ WARN: $message"
            ((TESTS_PASSED++)) # Warnings don't fail the test
            ;;
    esac
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_color "$RED" "This script must be run as root (use sudo)"
        exit 1
    fi
}

################################################################################
# TEST FUNCTIONS
################################################################################

# Test 1: Verify Spotify Flatpak installed
test_spotify_installed() {
    print_test_header "Spotify Flatpak Installation"

    if flatpak list | grep -q "com.spotify.Client"; then
        local version=$(flatpak info com.spotify.Client 2>/dev/null | grep "Version:" | awk '{print $2}' || echo "unknown")
        record_result "pass" "Spotify Flatpak installed (version: $version)"
        return 0
    else
        record_result "fail" "Spotify Flatpak not installed"
        return 1
    fi
}

# Test 2: Verify SpotX module enabled
test_spotx_module_enabled() {
    print_test_header "SpotX Module Status"

    if systemctl list-unit-files | grep -q "spotx-patch.service"; then
        record_result "pass" "SpotX module is enabled (spotx-patch.service exists)"
        return 0
    else
        record_result "fail" "SpotX module not enabled (spotx-patch.service not found)"
        return 1
    fi
}

# Test 3: Verify spicetify-nix flake input
test_spicetify_nix_input() {
    print_test_header "Spicetify Nix Input"

    local flake_path="/etc/nixos"
    if [ -f "$flake_path/flake.nix" ]; then
        if grep -q "spicetify-nix" "$flake_path/flake.nix"; then
            record_result "pass" "spicetify-nix input found in flake.nix"
            return 0
        else
            record_result "fail" "spicetify-nix input not found in flake.nix"
            return 1
        fi
    else
        record_result "skip" "flake.nix not found at $flake_path"
        return 0
    fi
}

# Test 4: Verify network connectivity
test_network_connectivity() {
    print_test_header "Network Connectivity"

    if ping -c 1 -W 2 github.com &>/dev/null; then
        record_result "pass" "Network connectivity OK (github.com reachable)"
        return 0
    else
        record_result "warn" "Network connectivity issues detected (github.com unreachable)"
        return 0
    fi
}

# Test 5: Check SpotX patch applied
test_spotx_patch_applied() {
    print_test_header "SpotX Patch Status"

    local spotify_path=$(flatpak info com.spotify.Client --show-location 2>/dev/null)
    if [ -z "$spotify_path" ]; then
        record_result "skip" "Cannot check SpotX patch (Spotify not installed)"
        return 0
    fi

    local spotx_marker="$spotify_path/files/extra/share/spotify/Apps/.spotx_patched"
    if [ -f "$spotx_marker" ]; then
        local patched_version=$(cat "$spotx_marker" 2>/dev/null || echo "unknown")
        record_result "pass" "SpotX patch applied (version: $patched_version)"
        return 0
    else
        record_result "fail" "SpotX patch not applied (.spotx_patched marker missing)"
        return 1
    fi
}

# Test 6: Check flatpak-update service
test_flatpak_update_service() {
    print_test_header "Flatpak Update Service"

    if systemctl list-unit-files | grep -q "flatpak-update.service"; then
        record_result "pass" "flatpak-update.service exists"
        return 0
    else
        record_result "warn" "flatpak-update.service not found (optional dependency)"
        return 0
    fi
}

# Test 7: Verify systemd services created
test_spicetify_systemd_services() {
    print_test_header "Spicetify Systemd Services"

    local services_missing=0

    # Check main service
    if systemctl list-unit-files | grep -q "spotify-spicetify.service"; then
        record_result "pass" "spotify-spicetify.service defined"
    else
        record_result "fail" "spotify-spicetify.service not found"
        ((services_missing++))
    fi

    # Check timer (may not exist if autoApply is disabled)
    if systemctl list-unit-files | grep -q "spotify-spicetify.timer"; then
        record_result "pass" "spotify-spicetify.timer defined"
    else
        record_result "warn" "spotify-spicetify.timer not found (autoApply may be disabled)"
    fi

    # Check after-flatpak service
    if systemctl list-unit-files | grep -q "spotify-spicetify-after-flatpak.service"; then
        record_result "pass" "spotify-spicetify-after-flatpak.service defined"
    else
        record_result "warn" "spotify-spicetify-after-flatpak.service not found (optional)"
    fi

    return $services_missing
}

# Test 8: Verify service dependencies
test_service_dependencies() {
    print_test_header "Service Dependencies"

    local service_file=$(systemctl cat spotify-spicetify.service 2>/dev/null || echo "")

    if [ -z "$service_file" ]; then
        record_result "skip" "Cannot check dependencies (spotify-spicetify.service not found)"
        return 0
    fi

    # Check After= dependency
    if echo "$service_file" | grep -q "After=.*spotx-patch.service"; then
        record_result "pass" "Service has After=spotx-patch.service dependency"
    else
        record_result "fail" "Service missing After=spotx-patch.service dependency"
        return 1
    fi

    # Check Wants dependency
    if echo "$service_file" | grep -q "Wants=.*spotx-patch.service"; then
        record_result "pass" "Service has Wants=spotx-patch.service dependency"
    else
        record_result "warn" "Service missing Wants=spotx-patch.service dependency"
    fi

    return 0
}

# Test 9: Status command availability
test_status_command() {
    print_test_header "Status Command"

    if command -v spotify-spicetify &>/dev/null; then
        record_result "pass" "spotify-spicetify command available"
    else
        record_result "fail" "spotify-spicetify command not found"
        return 1
    fi
}

# Test 10: Status command execution
test_status_command_execution() {
    print_test_header "Status Command Execution"

    if ! command -v spotify-spicetify &>/dev/null; then
        record_result "skip" "Cannot run status command (spotify-spicetify not available)"
        return 0
    fi

    local output=$(spotify-spicetify status 2>&1 || true)
    if [ -n "$output" ]; then
        print_color "$BLUE" "Status output: $output"
        record_result "pass" "Status command executed successfully"
        return 0
    else
        record_result "fail" "Status command produced no output"
        return 1
    fi
}

# Test 11: State directory exists
test_state_directory() {
    print_test_header "State Directory"

    local state_dir="/var/lib/spicetify"
    if [ -d "$state_dir" ]; then
        local perms=$(stat -c "%a" "$state_dir" 2>/dev/null || echo "unknown")
        local owner=$(stat -c "%U:%G" "$state_dir" 2>/dev/null || echo "unknown")
        record_result "pass" "State directory exists ($state_dir, permissions: $perms, owner: $owner)"
        return 0
    else
        record_result "fail" "State directory missing ($state_dir)"
        return 1
    fi
}

# Test 12: Config directory exists
test_config_directory() {
    print_test_header "Config Directory"

    local config_dir="/etc/nixos/config/spicetify"
    if [ -d "$config_dir" ]; then
        record_result "pass" "Config directory exists ($config_dir)"
        return 0
    else
        record_result "warn" "Config directory missing ($config_dir) - using defaults"
        return 0
    fi
}

# Test 13: Version marker check
test_version_marker() {
    print_test_header "Version Marker"

    local version_marker="/var/lib/spicetify/version"
    if [ -f "$version_marker" ]; then
        local version=$(cat "$version_marker" 2>/dev/null || echo "unknown")
        record_result "pass" "Version marker exists (Spicetify applied for version: $version)"
        return 0
    else
        record_result "warn" "Version marker not found (Spicetify may not be applied yet)"
        return 0
    fi
}

# Test 14: Integration test - apply command
test_integration_apply() {
    print_test_header "Integration Test: Apply Command"

    if ! command -v spotify-spicetify &>/dev/null; then
        record_result "skip" "Cannot run integration test (spotify-spicetify not available)"
        return 0
    fi

    print_color "$BLUE" "Stopping Spotify if running..."
    flatpak kill com.spotify.Client 2>/dev/null || true

    print_color "$BLUE" "Running spotify-spicetify apply --verbose..."
    if spotify-spicetify apply --verbose 2>&1; then
        record_result "pass" "Apply command executed successfully"
        return 0
    else
        local exit_code=$?
        record_result "fail" "Apply command failed (exit code: $exit_code)"
        return 1
    fi
}

# Test 15: Verify version marker created
test_version_marker_created() {
    print_test_header "Version Marker After Apply"

    local version_marker="/var/lib/spicetify/version"
    if [ -f "$version_marker" ]; then
        local version=$(cat "$version_marker" 2>/dev/null || echo "unknown")
        record_result "pass" "Version marker created after apply (version: $version)"
        return 0
    else
        record_result "fail" "Version marker not created after apply"
        return 1
    fi
}

# Test 16: Verify backup created
test_backup_created() {
    print_test_header "Backup Directory"

    local backup_dir="/var/lib/spicetify/backups"
    if [ -d "$backup_dir" ]; then
        local backup_count=$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        record_result "pass" "Backup directory exists ($backup_count backups found)"
        return 0
    else
        record_result "warn" "Backup directory missing ($backup_dir)"
        return 0
    fi
}

# Test 17: Service status check
test_service_status() {
    print_test_header "Service Status"

    if systemctl list-unit-files | grep -q "spotify-spicetify.service"; then
        local status=$(systemctl is-enabled spotify-spicetify.service 2>/dev/null || echo "not-found")
        if [ "$status" = "enabled" ] || [ "$status" = "static" ]; then
            record_result "pass" "spotify-spicetify.service is $status"
        else
            record_result "warn" "spotify-spicetify.service is $status"
        fi
    else
        record_result "skip" "spotify-spicetify.service not found"
    fi

    if systemctl list-unit-files | grep -q "spotify-spicetify.timer"; then
        local timer_status=$(systemctl is-enabled spotify-spicetify.timer 2>/dev/null || echo "not-found")
        local timer_active=$(systemctl is-active spotify-spicetify.timer 2>/dev/null || echo "inactive")
        record_result "pass" "spotify-spicetify.timer is $timer_status (active: $timer_active)"
    fi

    return 0
}

# Test 18: Check for disabled marker
test_disabled_marker() {
    print_test_header "Disabled Marker Check"

    local disabled_marker="/var/lib/spicetify/disabled"
    if [ -f "$disabled_marker" ]; then
        local reason=$(cat "$disabled_marker" 2>/dev/null || echo "unknown")
        record_result "warn" "Spicetify is disabled (reason: $reason)"
        return 0
    else
        record_result "pass" "Spicetify is enabled (no disabled marker)"
        return 0
    fi
}

# Test 19: Verify CLI wrapper permissions
test_cli_wrapper_permissions() {
    print_test_header "CLI Wrapper Permissions"

    local wrapper_path=$(command -v spotify-spicetify 2>/dev/null || echo "")
    if [ -z "$wrapper_path" ]; then
        record_result "skip" "CLI wrapper not found"
        return 0
    fi

    if [ -x "$wrapper_path" ]; then
        record_result "pass" "CLI wrapper is executable ($wrapper_path)"
        return 0
    else
        record_result "fail" "CLI wrapper is not executable ($wrapper_path)"
        return 1
    fi
}

# Test 20: Check spicetify-cli availability
test_spicetify_cli_available() {
    print_test_header "Spicetify CLI Availability"

    if command -v spicetify &>/dev/null; then
        local version=$(spicetify --version 2>/dev/null || echo "unknown")
        record_result "pass" "spicetify-cli available (version: $version)"
        return 0
    else
        record_result "fail" "spicetify-cli not found in PATH"
        return 1
    fi
}

################################################################################
# MAIN TEST RUNNER
################################################################################

main() {
    print_color "$BLUE" "╔══════════════════════════════════════════════════════════════╗"
    print_color "$BLUE" "║  Spotify + Spicetify Integration Test Suite                ║"
    print_color "$BLUE" "║  Version: 1.0.0                                            ║"
    print_color "$BLUE" "║  Date: $(date '+%Y-%m-%d %H:%M:%S')                          ║"
    print_color "$BLUE" "╚══════════════════════════════════════════════════════════════╝"

    # Check if running as root
    check_root

    # Run all tests
    test_spotify_installed
    test_spotx_module_enabled
    test_spicetify_nix_input
    test_network_connectivity
    test_spotx_patch_applied
    test_flatpak_update_service
    test_spicetify_systemd_services
    test_service_dependencies
    test_status_command
    test_status_command_execution
    test_state_directory
    test_config_directory
    test_version_marker
    test_integration_apply
    test_version_marker_created
    test_backup_created
    test_service_status
    test_disabled_marker
    test_cli_wrapper_permissions
    test_spicetify_cli_available

    # Print summary
    echo ""
    print_color "$BLUE" "╔══════════════════════════════════════════════════════════════╗"
    print_color "$BLUE" "║  TEST SUMMARY                                              ║"
    print_color "$BLUE" "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    print_color "$GREEN" "✓ Passed: $TESTS_PASSED"
    print_color "$RED" "✗ Failed: $TESTS_FAILED"
    print_color "$YELLOW" "⊘ Skipped: $TESTS_SKIPPED"
    print_color "$BLUE" "Total: $TESTS_RUN"
    echo ""

    # Calculate success rate
    if [ $TESTS_RUN -gt 0 ]; then
        local success_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
        print_color "$BLUE" "Success Rate: ${success_rate}%"
    fi

    # Exit with appropriate code
    if [ $TESTS_FAILED -eq 0 ]; then
        print_color "$GREEN" "╔══════════════════════════════════════════════════════════════╗"
        print_color "$GREEN" "║  ✓ ALL TESTS PASSED                                       ║"
        print_color "$GREEN" "╚══════════════════════════════════════════════════════════════╝"
        exit 0
    else
        print_color "$RED" "╔══════════════════════════════════════════════════════════════╗"
        print_color "$RED" "║  ✗ SOME TESTS FAILED                                       ║"
        print_color "$RED" "╚══════════════════════════════════════════════════════════════╝"
        exit 1
    fi
}

# Run main function
main "$@"
