#!/usr/bin/env bash
# Wrapper script to add NixOS tools to PATH
export PATH="/run/current-system/sw/bin:$PATH"

# Check if we're run as root
if [ "$(id -u)" = "0" ]; then
	exec "$@"
fi

# Run the command
exec "$@"
