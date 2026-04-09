#!/usr/bin/env bash
# Agenix Secrets Manager - Bootstrap Script
#
# One-time setup script to initialize the agenix skill environment.
# Handles dependency installation, config initialization, and validation.

set -euo pipefail

# ============================================================================
# COLORS
# ============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"
CONFIG_FILE="$CONFIG_DIR/agenix-skill.conf"

# ============================================================================
# FUNCTIONS
# ============================================================================

print_success() {
	echo -e "${GREEN}✓${RESET} $1"
}

print_error() {
	echo -e "${RED}✗${RESET} $1"
	if [ -n "${2:-}" ]; then
		echo -e "${BLUE}  →${RESET} $2"
	fi
}

print_warning() {
	echo -e "${YELLOW}⚠${RESET} $1"
}

print_info() {
	echo -e "${BLUE}ℹ${RESET} $1"
}

print_step() {
	echo -e "${CYAN}▶${RESET} $1"
}

# ============================================================================
# SETUP STEPS
# ============================================================================

check_nixos_dir() {
	print_step "Checking NixOS configuration directory"

	if [ -d "/etc/nixos" ]; then
		print_success "Found /etc/nixos"
		return 0
	else
		print_error "NixOS configuration not found" "Ensure you're on a NixOS system or run from /etc/nixos"
		return 1
	fi
}

check_python3() {
	print_step "Checking Python 3"

	if command -v python3 &>/dev/null; then
		PYTHON_VERSION=$(python3 --version)
		print_success "Python 3 is available: $PYTHON_VERSION"
		return 0
	else
		print_error "Python 3 not found" "Install Python 3 to continue"
		return 1
	fi
}

install_dependencies() {
	print_step "Checking dependencies"

	# Check if agenix is available
	if command -v agenix &>/dev/null; then
		print_success "agenix is already installed"
	else
		print_info "Installing agenix from GitHub..."
		nix build github:ryantm/agenix --out-link /tmp/agenix-installed || {
			print_error "Failed to build agenix"
			return 1
		}

		# Add to PATH temporarily for this session
		export PATH="/tmp/agenix-installed/bin:$PATH"

		print_success "agenix installed (temporary for this session)"
		print_warning "To install permanently, add to your NixOS configuration:"
		echo -e "${CYAN}  environment.systemPackages = [ pkgs.agenix ];${RESET}"
	fi

	# Check if ssh-to-age is available
	if command -v ssh-to-age &>/dev/null; then
		print_success "ssh-to-age is already installed"
	else
		print_info "Installing ssh-to-age..."
		nix-shell -p ssh-to-age --run which ssh-to-age || {
			print_error "Failed to install ssh-to-age"
			return 1
		}

		print_success "ssh-to-age installed"
		print_warning "To install permanently, add to your NixOS configuration:"
		echo -e "${CYAN}  environment.systemPackages = [ pkgs.ssh-to-age ];${RESET}"
	fi

	return 0
}

init_config() {
	print_step "Initializing configuration"

	# Create config directory if it doesn't exist
	mkdir -p "$CONFIG_DIR"

	# Initialize default config
	python3 "$SCRIPT_DIR/common.py" -c "import common; common.init_config(force=False)" || {
		print_error "Failed to initialize configuration"
		return 1
	}

	print_success "Configuration initialized at $CONFIG_FILE"
	print_info "Edit $CONFIG_FILE to customize settings"
}

validate_age_key() {
	print_step "Validating age key"

	# Try to detect the age key path
	if [ -f "$HOME/.age/key.txt" ]; then
		print_success "Age key found at $HOME/.age/key.txt"
		return 0
	else
		print_warning "Age key not found at default location"
		print_info "Generate an age key with: age-keygen -o ~/.age/key.txt"
		read -p "Age key path (or press Enter to skip): " AGE_KEY_PATH
		if [ -z "$AGE_KEY_PATH" ]; then
			return 1
		fi
		if [ ! -f "$AGE_KEY_PATH" ]; then
			print_error "Age key file not found: $AGE_KEY_PATH"
			return 1
		fi
		python3 "$SCRIPT_DIR/common.py" -c "import common; config = common.load_config() or common.DEFAULT_CONFIG; config['user']['age_key_path'] = '$AGE_KEY_PATH'; common.save_config(config)" || {
			print_error "Failed to update configuration"
			return 1
		}
		print_success "Age key configured"
		return 0
	fi
}

validate_secrets_nix() {
	print_step "Validating secrets.nix"

	local secrets_nix_path="/etc/nixos/secrets.nix"

	if [ ! -f "$secrets_nix_path" ]; then
		print_warning "secrets.nix not found"
		print_info "Run 'python3 scripts/add_secret.py <name> <value>' to create your first secret"
		return 1
	else
		print_success "secrets.nix found"
		return 0
	fi
}

collect_host_keys() {
	print_step "Collecting host keys"

	print_info "This step is optional but recommended for automatic decryption"
	print_info "Without host keys, you'll need your age key for each rebuild"
	read -p "Collect host keys now? (y/N): " COLLECT_KEYS

	if [ "$COLLECT_KEYS" != "y" ] && [ "$COLLECT_KEYS" != "Y" ]; then
		print_info "Skipping host key collection. Run later with:"
		echo -e "${CYAN}  python3 scripts/setup_host_keys.py --help${RESET}"
		return 0
	fi

	# Check for get_host_keys.sh
	local get_keys_script="$SCRIPT_DIR/get_host_keys.sh"

	if [ ! -f "$get_keys_script" ]; then
		print_warning "get_host_keys.sh not found"
		print_info "Run manual key collection per HOST_KEY_SETUP_GUIDE.md"
		return 1
	fi

	# Run the script
	"$get_keys_script" || {
		print_error "Failed to collect host keys"
		return 1
	}

	print_success "Host keys collected and added to secrets.nix"
	return 0
}

test_setup() {
	print_step "Testing setup"

	print_info "Running validation script..."

	if [ -f "$SCRIPT_DIR/validate.py" ]; then
		python3 "$SCRIPT_DIR/validate.py" || {
			print_warning "Validation found issues (shown above)"
			return 0
		}
		print_success "Setup is valid!"
		return 0
	else
		print_error "validate.py not found"
		return 1
	fi
}

print_next_steps() {
	echo ""
	echo -e "${CYAN}========================================${RESET}"
	print_info "Next steps:"
	echo -e "${CYAN}========================================${RESET}"
	echo ""
	echo "1. Add your first secret:"
	echo -e "${CYAN}   python3 scripts/add_secret.py my-secret 'secret-value'${RESET}"
	echo ""
	echo "2. Add secrets to multiple hosts:"
	echo -e "${CYAN}   python3 scripts/add_secret_multihost.py shared-secret 'value' --hosts zephyr,forge${RESET}"
	echo ""
	echo "3. Validate your configuration:"
	echo -e "${CYAN}   python3 scripts/validate.py${RESET}"
	echo ""
	echo "4. Rebuild your host:"
	echo -e "${CYAN}   sudo nixos-rebuild switch --flake .#<hostname>${RESET}"
	echo ""
	echo "5. Access decrypted secrets:"
	echo -e "${CYAN}   cat /run/agenix/<secret-name>${RESET}"
	echo ""
	echo "For more help, see:"
	echo -e "${CYAN}   skills/agenix-secrets/README.md${RESET}"
	echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
	echo ""
	echo -e "${CYAN}========================================${RESET}"
	echo -e "${CYAN}Agenix Secrets Manager - Bootstrap${RESET}"
	echo -e "${CYAN}========================================${RESET}"
	echo ""

	# Run all setup steps
	check_nixos_dir || exit 1
	check_python3 || exit 1
	install_dependencies || exit 1
	init_config || exit 1
	validate_age_key || exit 1
	validate_secrets_nix || exit 0
	collect_host_keys || exit 0
	test_setup || exit 1

	print_next_steps
}

main "$@"
