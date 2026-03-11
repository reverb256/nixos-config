# Auto-Update LM Studio Models Systemd Timer

Automatically checks for new LM Studio models and updates them.

## Installation

Create the systemd user service and timer:

```bash
# Create service file
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/lm-studio-auto-update.service << 'EOF'
[Unit]
Description=Auto-update LM Studio Models
After=network.target lm-studio.service ai-inference-gateway.service

[Service]
Type=oneshot
ExecStart=/etc/nixos/scripts/auto-update-models.py
WorkingDirectory=/etc/nixos
Environment=PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin

[Install]
WantedBy=multi-user.target
EOF

# Create timer file (runs daily at 3 AM)
cat > ~/.config/systemd/user/lm-studio-auto-update.timer << 'EOF'
[Unit]
Description=Daily LM Studio model auto-update

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start
systemctl --user daemon-reload
systemctl --user enable lm-studio-auto-update.timer
systemctl --user start lm-studio-auto-update.timer
```

## Manual Commands

```bash
# Check timer status
systemctl --user status lm-studio-auto-update.timer

# Check next scheduled run
systemctl --user list-timers | grep lm-studio

# Trigger manual update
systemctl --user start lm-studio-auto-update.service

# View logs
journalctl --user -u lm-studio-auto-update -f

# Disable auto-update
systemctl --user disable lm-studio-auto-update.timer
systemctl --user stop lm-studio-auto-update.timer
```

## Schedule Customization

Edit `~/.config/systemd/user/lm-studio-auto-update.timer`:

```ini
# Every 6 hours
OnCalendar=*-*-* 0/6:00:00

# Every week on Sunday at 2 AM
OnCalendar=Sun *-*-* 02:00:00

# Hourly (not recommended - resource intensive)
OnCalendar=hourly
```

## Integration with AI Gateway

The auto-update script automatically:
1. Checks LM Studio health
2. Identifies missing models
3. Downloads new models (if --download flag)
4. Loads models with optimal settings
5. Refreshes gateway to recognize them
6. Tests new models

## Dependencies

- LM Studio running on port 1234
- AI inference gateway running on port 8080
- API key at `/run/agenix/lm-studio-api-key`

## Troubleshooting

**Timer not triggering:**
```bash
# Check if timer is active
systemctl --user list-timers

# Check if service ran successfully
journalctl --user -u lm-studio-auto-update -n 5
```

**Script fails with httpx error:**
```bash
# Script needs httpx, just command wraps it automatically
just models
```

**LM Studio not accessible:**
```bash
# Check LM Studio status
curl http://127.0.0.1:1234/v1/models

# Start LM Studio
just lm-studio-start
```

**Gateway not refreshing:**
```bash
# Check gateway health
curl http://127.0.0.1:8080/health

# Check gateway logs
journalctl -u ai-inference-gateway -f
```

## Alternative: Cron Job

If systemd timers aren't working, use cron:

```bash
# Add to crontab
crontab -e

# Add line for daily 3 AM update
0 3 * * * /etc/nixos/scripts/auto-update-models.py >> ~/.local/share/lm-studio-auto-update.log 2>&1
```
