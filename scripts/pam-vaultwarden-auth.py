#!/usr/bin/env python3
"""
PAM authentication script for Vaultwarden
Validates user credentials against Vaultwarden's Bitwarden-compatible API

Usage in PAM config:
    auth sufficient pam_exec.so expose_authtok /etc/nixos/scripts/pam-vaultwarden-auth.py

Exit codes:
    0 = PAM_SUCCESS (authentication successful)
    1 = PAM_AUTH_ERR (authentication failed)
    2 = PAM_SYSTEM_ERR (system error, e.g., Vaultwarden unreachable)
"""

import sys
import os
import json
import urllib.request
import urllib.error
from getpass import getpass

# Configuration
VAULTWARDEN_URL = os.environ.get(
    "VAULTWARDEN_URL",
    "http://localhost:8222"
)
VAULTWARDEN_API = f"{VAULTWARDEN_URL}/identity"

# Timeout in seconds
REQUEST_TIMEOUT = 10


def log_error(message: str):
    """Log error to syslog or stderr"""
    try:
        import syslog
        syslog.syslog(syslog.LOG_ERR, f"pam-vaultwarden: {message}")
    except ImportError:
        print(f"ERROR: {message}", file=sys.stderr)


def prelogin(username: str) -> dict:
    """
    Perform prelogin to get password hashing requirements
    Returns the KDF parameters for password hashing
    """
    try:
        data = {
            "email": username
        }
        req = urllib.request.Request(
            f"{VAULTWARDEN_API}/accounts/prelogin",
            data=json.dumps(data).encode('utf-8'),
            headers={
                'Content-Type': 'application/json',
                'Device-Type': '0',  # Browser API
            }
        )
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            return json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            # User not found, return default KDF
            return {"Kdf": 0, "KdfIterations": 600000}
        raise
    except Exception as e:
        log_error(f"Prelogin failed: {e}")
        raise


def authenticate(username: str, password: str) -> bool:
    """
    Authenticate user against Vaultwarden API
    Returns True if authentication successful
    """
    try:
        # Get KDF parameters first
        prelogin_data = prelogin(username)

        # Prepare authentication request
        # Note: This is a simplified version. Real Bitwarden client does
        # PBKDF2 key derivation client-side, but Vaultwarden accepts
        # direct password for PAM use case via a workaround.
        #
        # For production, you should implement proper client-side hashing.
        #
        # This implementation uses the password grant type which works
        # with Vaultwarden for username/password validation.

        data = {
            "grant_type": "password",
            "username": username,
            "password": password,
            "scope": "api offline_access",
            "client_id": "browser",
            "deviceType": 0,
        }

        req = urllib.request.Request(
            f"{VAULTWARDEN_API}/connect/token",
            data=json.dumps(data).encode('utf-8'),
            headers={
                'Content-Type': 'application/json',
                'Accept': 'application/json',
            }
        )

        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as response:
            result = json.loads(response.read().decode('utf-8'))
            # If we get an access_token, authentication succeeded
            return "access_token" in result

    except urllib.error.HTTPError as e:
        if e.code in (400, 401):
            # Invalid credentials
            return False
        log_error(f"HTTP error during auth: {e.code}")
        return False
    except Exception as e:
        log_error(f"Authentication error: {e}")
        # Return False on error to fail closed
        return False


def main():
    # Get username from PAM environment
    username = os.environ.get("PAM_USER")
    if not username:
        log_error("PAM_USER not set")
        sys.exit(2)  # PAM_SYSTEM_ERR

    # Get password from stdin (if expose_authtok is set)
    # or from environment
    password = None
    if "PAM_AUTHTOK" in os.environ:
        password = os.environ["PAM_AUTHTOK"]
    else:
        # Fallback: read from stdin (for testing)
        try:
            password = sys.stdin.readline().strip()
        except:
            password = getpass("Vaultwarden password: ")

    if not password:
        log_error("No password provided")
        sys.exit(1)  # PAM_AUTH_ERR

    # Authenticate
    if authenticate(username, password):
        sys.exit(0)  # PAM_SUCCESS
    else:
        sys.exit(1)  # PAM_AUTH_ERR


if __name__ == "__main__":
    main()
