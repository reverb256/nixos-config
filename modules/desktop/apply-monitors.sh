#!/usr/bin/env bash
# Quick script to manually apply monitor configuration
# Run this when monitors get messed up or after connecting/disconnecting the TV

plasma-monitor-setup

if [ $? -eq 0 ]; then
    echo "✓ Monitor configuration applied successfully!"
    echo "Check /tmp/plasma-monitor-setup.log for details"
else
    echo "✗ Failed to apply monitor configuration"
    echo "Check /tmp/plasma-monitor-setup.log for errors"
    exit 1
fi
