#!/usr/bin/env python3
"""
Common utilities for Agenix Secrets Manager.

This module provides shared functionality across all scripts including:
- Path resolution and validation
- Dependency checking and auto-installation
- Color-coded output
- Error handling with actionable suggestions
- File backup and rollback
- Configuration file support
"""

import os
import subprocess
import shutil
import re
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, List, Tuple, Any
import configparser

# ============================================================================
# CONFIGURATION
# ============================================================================


# Color codes for terminal output
class Colors:
    """ANSI color codes for terminal output."""

    RESET = "\033[0m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN = "\033[36m"
    BOLD = "\033[1m"


# Configuration file locations
CONFIG_PATH = Path.home() / ".config" / "agenix-skill.conf"
DEFAULT_CONFIG = {
    "user": {
        "name": os.getenv("USER", "j_kro"),
        "age_key_path": str(Path.home() / ".age" / "key.txt"),
        "nixos_dir": "/etc/nixos",
    },
    "agenix": {
        "install_source": "github:ryantm/agenix",
        "auto_install": "true",
    },
}

# ============================================================================
# PATH RESOLUTION
# ============================================================================


def get_nixos_dir() -> Path:
    """
    Get the NixOS configuration directory.

    Priority:
    1. Config file setting
    2. Current directory (if it's /etc/nixos)
    3. Environment variable AGENIX_NIXOS_DIR
    4. Default to /etc/nixos

    Returns:
        Path to NixOS configuration directory
    """
    config = load_config()

    if config and "user" in config and "nixos_dir" in config["user"]:
        nixos_dir = Path(config["user"]["nixos_dir"])
        if nixos_dir.exists():
            return nixos_dir

    # Check current directory
    current_dir = Path.cwd()
    if current_dir.name == "nixos" and str(current_dir).endswith("/etc/nixos"):
        return current_dir

    # Check environment variable
    env_dir = os.getenv("AGENIX_NIXOS_DIR")
    if env_dir:
        return Path(env_dir)

    # Default
    return Path("/etc/nixos")


def get_secrets_dir() -> Path:
    """
    Get the secrets directory.

    Returns:
        Path to secrets directory (usually /etc/nixos/secrets)
    """
    nixos_dir = get_nixos_dir()
    return nixos_dir / "secrets"


def get_secrets_nix_path() -> Path:
    """
    Get the path to secrets.nix.

    Returns:
        Path to secrets.nix
    """
    nixos_dir = get_nixos_dir()
    return nixos_dir / "secrets.nix"


def get_age_identity_path(user: Optional[str] = None) -> Path:
    """
    Get the path to the age identity (private key).

    Args:
        user: Username (defaults to config or environment user)

    Returns:
        Path to age identity file
    """
    config = load_config()

    if config and "user" in config and "age_key_path" in config["user"]:
        return Path(config["user"]["age_key_path"])

    # Default location
    username = user or os.getenv("USER", "j_kro")
    return Path(f"/home/{username}/.age/key.txt")


def get_hosts_dir() -> Path:
    """
    Get the hosts configuration directory.

    Returns:
        Path to hosts directory (usually /etc/nixos/hosts)
    """
    nixos_dir = get_nixos_dir()
    return nixos_dir / "hosts"


def resolve_secret_path(secret_name: str) -> Path:
    """
    Resolve the full path to a secret file.

    Handles both "secret.age" and "secrets/secret.age" formats.

    Args:
        secret_name: Name of the secret (with or without .age extension)

    Returns:
        Full Path to the secret file
    """
    # Ensure .age extension
    if not secret_name.endswith(".age"):
        secret_name = f"{secret_name}.age"

    secrets_dir = get_secrets_dir()

    # Try secrets/ directory first
    if "/" in secret_name:
        # Already has path prefix
        return get_nixos_dir() / secret_name
    else:
        # Try secrets/ directory
        path = secrets_dir / secret_name
        if path.exists():
            return path

        # Try root directory
        return get_nixos_dir() / secret_name


# ============================================================================
# CONFIGURATION FILE MANAGEMENT
# ============================================================================


def load_config() -> Dict[str, Dict[str, str]]:
    """
    Load configuration from ~/.config/agenix-skill.conf.

    Returns:
        Configuration dict or default if not found
    """
    if not CONFIG_PATH.exists():
        return DEFAULT_CONFIG

    config = configparser.ConfigParser()
    config.read(CONFIG_PATH)

    result = {}
    for section in config.sections():
        result[section] = dict(config.items(section))

    return result


def save_config(config: Dict[str, Dict[str, str]]) -> None:
    """
    Save configuration to ~/.config/agenix-skill.conf.

    Args:
        config: Configuration dict to save
    """
    config_parser = configparser.ConfigParser()

    for section, items in config.items():
        config_parser.add_section(section)
        for key, value in items.items():
            config_parser.set(section, key, value)

    # Create config directory if needed
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)

    with open(CONFIG_PATH, "w") as f:
        config_parser.write(f)


def init_config(force: bool = False) -> bool:
    """
    Initialize default configuration file.

    Args:
        force: Overwrite existing config

    Returns:
        True if successful, False otherwise
    """
    if CONFIG_PATH.exists() and not force:
        print_info(f"Configuration file already exists at {CONFIG_PATH}")
        return False

    save_config(DEFAULT_CONFIG)
    print_success(f"Created default configuration at {CONFIG_PATH}")
    return True


# ============================================================================
# DEPENDENCY MANAGEMENT
# ============================================================================


def check_dependencies() -> Tuple[bool, List[str]]:
    """
    Check for required dependencies.

    Returns:
        Tuple of (all_found, missing_deps)
    """
    dependencies = {
        "agenix": "Required for encryption/decryption",
        "ssh-to-age": "Required for host key setup",
    }

    found = {}
    missing = []

    for dep, description in dependencies.items():
        if shutil.which(dep):
            found[dep] = True
        else:
            missing.append((dep, description))

    return len(missing) == 0, missing


def install_dependency(dependency: str, force: bool = False) -> bool:
    """
    Install a dependency using nix.

    Args:
        dependency: Name of dependency to install
        force: Install even if already present

    Returns:
        True if successful, False otherwise
    """
    if not force and shutil.which(dependency):
        print_info(f"{dependency} is already installed")
        return True

    print_info(f"Installing {dependency}...")

    # Build agenix from GitHub
    if dependency == "agenix":
        result = subprocess.run(
            [
                "nix",
                "build",
                "github:ryantm/agenix",
                "--out-link",
                "/tmp/agenix-installed",
            ],
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            print_error(f"Failed to build agenix: {result.stderr}")
            return False

        # Add to PATH
        agenix_bin = Path("/tmp/agenix-installed/bin")
        if not agenix_bin.exists():
            print_error("Agenix installation failed")
            return False

        # Update PATH for current process
        current_path = os.environ.get("PATH", "")
        os.environ["PATH"] = str(agenix_bin) + ":" + current_path

        # Print instruction for persistent PATH
        print_warning(f"\n⚠ {dependency} installed temporarily for this session")
        print_info("To make it permanent, add to your PATH:")
        print_cyan(f"  export PATH='{str(agenix_bin)}:$PATH'")
        return True

    # Use nix-shell for other deps
    result = subprocess.run(
        ["nix-shell", "-p", dependency, "--run", "which", dependency],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        print_error(f"Failed to install {dependency}")
        return False

    # Note: nix-shell only makes it available during shell execution
    # Users need to install it permanently in their NixOS config
    print_warning(f"\n⚠ {dependency} installed temporarily via nix-shell")
    print_info("To install permanently, add to your NixOS configuration:")
    print_cyan(f"  environment.systemPackages = [ pkgs.{dependency} ];")
    return True


def ensure_dependencies(
    dependencies: Optional[List[str]] = None, auto_install: bool = False
) -> bool:
    """
    Ensure all required dependencies are available.

    Args:
        dependencies: List of specific deps to check (None for all)
        auto_install: Automatically install missing dependencies

    Returns:
        True if all available, False otherwise
    """
    all_found, missing = check_dependencies()

    if all_found:
        return True

    if not auto_install:
        print_error("Missing dependencies:")
        for dep, desc in missing:
            print(f"  ✗ {dep}: {desc}")
        print_info("\nInstall manually or run with --auto-install flag")
        return False

    print_warning(f"Missing {len(missing)} dependencies, installing automatically...")
    success = True
    for dep, desc in missing:
        if dependencies is None or dep in dependencies:
            if not install_dependency(dep):
                success = False

    return success


# ============================================================================
# OUTPUT UTILITIES
# ============================================================================


def print_success(message: str) -> None:
    """Print success message in green."""
    print(f"{Colors.GREEN}✓{Colors.RESET} {message}")


def print_error(message: str, suggestion: Optional[str] = None) -> None:
    """
    Print error message in red with optional actionable suggestion.

    Args:
        message: Error message
        suggestion: Actionable fix
    """
    print(f"{Colors.RED}✗{Colors.RESET} {message}")
    if suggestion:
        print_info(f"  → {suggestion}")


def print_warning(message: str) -> None:
    """Print warning message in yellow."""
    print(f"{Colors.YELLOW}⚠{Colors.RESET} {message}")


def print_info(message: str) -> None:
    """Print informational message in blue."""
    print(f"{Colors.BLUE}ℹ{Colors.RESET} {message}")


def print_cyan(message: str) -> None:
    """Print message in cyan."""
    print(f"{Colors.CYAN}{message}{Colors.RESET}")


def print_step(message: str) -> None:
    """Print step message with cyan arrow."""
    print(f"{Colors.CYAN}▶{Colors.RESET} {message}")


# ============================================================================
# FILE OPERATIONS
# ============================================================================


def backup_file(filepath: Path) -> Optional[Path]:
    """
    Create a timestamped backup of a file.

    Args:
        filepath: Path to file to backup

    Returns:
        Path to backup file or None if original doesn't exist
    """
    if not filepath.exists():
        return None

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = filepath.parent / f"{filepath.name}.backup_{timestamp}"

    shutil.copy2(filepath, backup_path)
    print_info(f"Backup created: {backup_path.name}")
    return backup_path


def rollback_to_backup(filepath: Path, keep_backup: bool = True) -> bool:
    """
    Rollback a file to its most recent backup.

    Args:
        filepath: Original file path
        keep_backup: Keep the backup file after rollback

    Returns:
        True if successful, False otherwise
    """
    # Find backups
    backups = sorted(
        filepath.parent.glob(f"{filepath.name}.backup_*"),
        reverse=True,
    )

    if not backups:
        print_warning(f"No backups found for {filepath.name}")
        return False

    latest_backup = backups[0]

    # Restore
    shutil.copy2(latest_backup, filepath)

    if not keep_backup:
        latest_backup.unlink()
        print_info(f"Backup {latest_backup.name} removed after restore")
    else:
        print_info(f"Backup {latest_backup.name} kept")

    print_success(f"Rolled back {filepath.name} to {latest_backup.name}")
    return True


def clean_old_backups(filepath: Path, keep: int = 5) -> int:
    """
    Clean old backups, keeping only the most recent ones.

    Args:
        filepath: Original file path
        keep: Number of backups to keep

    Returns:
        Number of backups removed
    """
    backups = sorted(
        filepath.parent.glob(f"{filepath.name}.backup_*"),
        reverse=True,
    )

    if len(backups) <= keep:
        return 0

    removed = backups[keep:]
    for backup in removed:
        backup.unlink()

    print_info(f"Cleaned {len(removed)} old backup(s)")
    return len(removed)


# ============================================================================
# SECRETS.NIX PARSING
# ============================================================================


def parse_secrets_nix(
    secrets_nix_path: Optional[Path] = None,
) -> Optional[Dict[str, Any]]:
    """
    Parse secrets.nix and extract users, hosts, and secret entries.

    Args:
        secrets_nix_path: Path to secrets.nix (uses default if None)

    Returns:
        Dict with 'users', 'hosts', 'secrets' keys or None on error
    """
    if secrets_nix_path is None:
        secrets_nix_path = get_secrets_nix_path()

    if not secrets_nix_path.exists():
        print_error(f"secrets.nix not found: {secrets_nix_path}")
        return None

    with open(secrets_nix_path, "r") as f:
        content = f.read()

    result = {"users": {}, "hosts": {}, "secrets": {}}

    # Parse users
    users_match = re.search(r"users\s*=\s*{([^}]+)};", content, re.DOTALL)
    if users_match:
        for match in re.finditer(r'(\w+)\s*=\s*"([^"]+)"', users_match.group(1)):
            result["users"][match.group(1)] = match.group(2)

    # Parse hosts
    hosts_match = re.search(r"hosts\s*=\s*{([^}]+)};", content, re.DOTALL)
    if hosts_match:
        for match in re.finditer(r'(\w+)\s*=\s*"([^"]+)"', hosts_match.group(1)):
            result["hosts"][match.group(1)] = match.group(2)

    # Parse secrets
    for match in re.finditer(
        r'"([^"]+\.age)"\.publicKeys\s*=\s*\[([^\]]+)\];', content
    ):
        secret_name = match.group(1)
        keys_content = match.group(2)

        # Parse keys (users.xxx or hosts.xxx)
        keys = []
        for key_match in re.finditer(r"(users\.|hosts\.)(\w+)", keys_content):
            key_type, key_name = key_match.groups()
            keys.append((key_type, key_name))

        result["secrets"][secret_name] = keys

    return result


# ============================================================================
# DRY RUN SUPPORT
# ============================================================================


class DryRunManager:
    """Context manager for dry-run operations."""

    def __init__(self, dry_run: bool = False):
        self.dry_run = dry_run
        self.pending_operations = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.dry_run:
            print_warning("\n" + "=" * 60)
            print_info("DRY RUN MODE - No changes were made")
            print_info("Review the operations above before running without --dry-run")
            print("=" * 60)

    def record_write(self, filepath: Path, content: str, description: str) -> None:
        """Record a file write operation."""
        if self.dry_run:
            self.pending_operations.append(
                {
                    "type": "write",
                    "file": str(filepath),
                    "description": description,
                }
            )
            print_cyan(f"  [DRY RUN] Would write: {filepath}")
            print_cyan(f"              {description}")
        else:
            # Perform actual write
            with open(filepath, "w") as f:
                f.write(content)

    def record_backup(self, filepath: Path) -> None:
        """Record a backup operation."""
        if self.dry_run:
            self.pending_operations.append(
                {
                    "type": "backup",
                    "file": str(filepath),
                }
            )
            print_cyan(f"  [DRY RUN] Would backup: {filepath}")
        else:
            backup_file(filepath)


# ============================================================================
# VALIDATION
# ============================================================================


def validate_secret_name(secret_name: str) -> Tuple[bool, Optional[str]]:
    """
    Validate a secret name.

    Args:
        secret_name: Name to validate

    Returns:
        Tuple of (is_valid, error_message)
    """
    if not secret_name:
        return False, "Secret name cannot be empty"

    if secret_name.startswith("-") or secret_name.startswith("_"):
        return False, "Secret name cannot start with - or _"

    # Check for invalid characters (alphanumeric, dash, underscore, dot, slash)
    if not re.match(r"^[\w./-]+$", secret_name):
        return False, "Secret name can only contain letters, numbers, -, _, /, and ."

    if secret_name.endswith(".age"):
        return False, "Secret name should not include .age extension"

    return True, None


def validate_host(
    hostname: str, config: Optional[Dict] = None
) -> Tuple[bool, Optional[str]]:
    """
    Validate a hostname against configuration.

    Args:
        hostname: Hostname to validate
        config: Secrets configuration dict (uses default if None)

    Returns:
        Tuple of (is_valid, error_message)
    """
    if config is None:
        config = parse_secrets_nix()

    if config is None:
        return False, "Could not load secrets.nix"

    if "hosts" not in config or hostname not in config["hosts"]:
        return False, f"Host '{hostname}' not found in secrets.nix"

    return True, None


# ============================================================================
# MAIN UTILITIES
# ============================================================================


def check_writable(filepath: Path) -> bool:
    """
    Check if a file is writable.

    Args:
        filepath: Path to check

    Returns:
        True if writable, False otherwise
    """
    if not filepath.exists():
        return os.access(filepath.parent, os.W_OK)

    return os.access(filepath, os.W_OK)


def print_summary(operations: List[Dict[str, str]]) -> None:
    """
    Print a summary of operations performed.

    Args:
        operations: List of operation dicts with 'type', 'file', 'description'
    """
    if not operations:
        return

    print("\n" + "=" * 60)
    print_info("Summary of operations:")
    print("=" * 60)

    by_type = {}
    for op in operations:
        op_type = op["type"]
        if op_type not in by_type:
            by_type[op_type] = 0
        by_type[op_type] += 1

    for op_type, count in sorted(by_type.items()):
        print(f"  {op_type}: {count} operation(s)")

    print(f"  Total: {len(operations)} operations")
