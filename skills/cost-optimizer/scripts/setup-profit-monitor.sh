#!/usr/bin/env bash
# Setup profit monitoring systemd service
# Usage: ./setup-profit-monitor.sh <electricity_rate> <min_profit_margin>

set -euo pipefail

ELECTRICITY_RATE=${1:-0.12}
MIN_PROFIT=${2:-0.10}

SCRIPT_DIR="/etc/nixos/scripts"
SERVICE_FILE="/etc/systemd/system/mining-profit-check.service"
TIMER_FILE="/etc/systemd/system/mining-profit-check.timer"

# Create the monitor script (if not exists)
if [ ! -f "$SCRIPT_DIR/profit-monitor.sh" ]; then
    echo "Error: profit-monitor.sh not found in $SCRIPT_DIR"
    echo "Please ensure the cost-optimizer skill scripts are installed."
    exit 1
fi

# Create systemd service
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Check mining profitability and pause if unprofitable
After=network.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/profit-monitor.sh $ELECTRICITY_RATE $MIN_PROFIT
# If unprofitable (exit 1), stop mining services
ExecStopPost=/bin/bash -c 'systemctl stop xmrig@* lolminer-* 2>/dev/null || true'
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create systemd timer (check hourly)
cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Hourly mining profitability check
Requires=mining-profit-check.service

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reload and enable
systemctl daemon-reload
systemctl enable mining-profit-check.timer
systemctl start mining-profit-check.timer

echo "✓ Profit monitoring installed!"
echo "  Electricity rate: \$$ELECTRICITY_RATE/kWh"
echo "  Minimum profit: \$$MIN_PROFIT per GPU per day"
echo ""
echo "Check status with:"
echo "  systemctl status mining-profit-check.timer"
echo "  journalctl -u mining-profit-check -f"
