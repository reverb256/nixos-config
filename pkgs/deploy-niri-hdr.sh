#!/usr/bin/env bash
set -euo pipefail

# Deploy niri-hdr binary from cargo build to system location.
# Run after: cd /tmp/niri-hdr && cargo build --release
# This replaces the running niri binary.

echo "Stopping current niri session..."
niri msg action quit 2>/dev/null || true
sleep 1

echo "Backing up old niri binary..."
sudo cp /run/current-system/sw/bin/niri /usr/local/bin/niri-stock

echo "Installing HDR fork..."
sudo cp /tmp/niri-hdr/target/release/niri /usr/local/bin/niri-hdr

echo "Done. Restart your niri session (sddm login or uwsm restart)."
