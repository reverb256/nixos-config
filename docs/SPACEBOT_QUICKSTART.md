# Spacebot Quick Start - Deploy Now!

Complete step-by-step guide to get Spacebot running on your NixOS system.

## Prerequisites

✅ You already have:
- NixOS with Flakes enabled
- AI Gateway running on port 8080
- LM Studio running on port 1234
- Agenix for secret management

## Step 1: Generate Discord Bot Token

Run the setup script (you created above):

```bash
/etc/nixos/scripts/setup-spacebot-token.sh
```

This will:
1. Show you how to get a Discord bot token
2. Prompt you to paste your token
3. Encrypt it with your age key
4. Save it to `/etc/nixos/secrets/spacebot-discord-token.age`

### Manual Alternative

If you prefer to do it manually:

```bash
# Get your age public key
grep -oP 'public key: \K.*' /home/j_kro/.age/key.txt

# Encrypt your Discord bot token (replace YOUR_TOKEN with actual token)
echo "YOUR_DISCORD_BOT_TOKEN" | age -r YOUR_AGE_PUBLIC_KEY > /etc/nixos/secrets/spacebot-discord-token.age
```

## Step 2: Rebuild NixOS

```bash
cd /etc/nixos
sudo nixos-rebuild switch
```

This will:
- Install Podman
- Create Spacebot configuration
- Set up systemd service
- Configure firewall

## Step 3: Start Spacebot

```bash
# Enable auto-start on boot
sudo systemctl enable spacebot

# Start Spacebot now
sudo systemctl start spacebot

# Check status
sudo systemctl status spacebot
```

Expected output:
```
● spacebot.service - Spacebot AI Agent
     Loaded: loaded (/etc/systemd/system/spacebot.service; enabled; preset: disabled)
     Active: active (running) since Wed 2026-03-04 20:00:00 CST; 5s ago
   Main PID: 12345 (spacebot)
      Tasks: 42 (limit: 4915)
     Memory: 150M (peak: 200M)
        CPU: 2.3s
     CGroup: /system.slice/spacebot.service
             └─12345 podman run --name spacebot ...
```

## Step 4: Verify It's Working

### Check Container Status

```bash
podman ps | grep spacebot
```

Expected output:
```
CONTAINER ID  IMAGE                                      COMMAND     CREATED     STATUS            NAMES
abc123def456  ghcr.io/spacedriveapp/spacebot:latest    /bin/sh     5 mins ago  Up 5 minutes ago  spacebot
```

### Check Web UI

```bash
curl http://localhost:19898
```

Should return HTML (the Spacebot web UI).

### Check Logs

```bash
sudo journalctl -u spacebot -f
```

Look for:
- `Starting webhook server on port 19898`
- `Connected to Discord gateway`
- No error messages

## Step 5: Invite Bot to Discord Server

### Create OAuth URL

1. Go to https://discord.com/developers/applications
2. Select your application (or create a new one)
3. Go to **OAuth2** > **URL Generator**
4. Select scopes:
   - ✅ `bot`
   - ✅ `applications.commands`
5. Select Bot Permissions:
   - ✅ Send Messages
   - ✅ Read Messages/View Channels
   - ✅ Read Message History
   - ✅ Add Reactions
   - ✅ Use Slash Commands
   - ✅ Embed Links
   - ✅ Attach Files
6. Copy the generated URL at the bottom
7. Open it in your browser and select a server

### Alternative Quick Invite URL

This URL includes all necessary permissions (replace `CLIENT_ID` with your application's client ID):

```
https://discord.com/api/oauth2/authorize?client_id=CLIENT_ID&permissions=274878024768&scope=bot%20applications.commands
```

## Step 6: Test Your Bot

In your Discord server:

1. Go to a channel where the bot has access
2. Type: `@YourBotName hello`
3. The bot should respond!

If it doesn't respond:

```bash
# Check logs for errors
sudo journalctl -u spacebot -n 100 --no-pager

# Verify bot token is correct
sudo cat /run/agenix/spacebot-discord-token
```

## How It Works

```
Your Discord message
       ↓
   Discord API
       ↓
Spacebot Container (Podman)
       ↓
  AI Gateway (localhost:8080)
       ↓
  LM Studio (localhost:1234)
       ↓
    AI Response
       ↓
   Back to Discord
```

## Accessing Spacebot

### Web UI

Open your browser:

```
http://localhost:19898
```

From other machines on your Tailscale network:

```
http://zephyr:19898
```

### What You Can Do

- **Configure agents**: Set personality, behavior, routing
- **View conversations**: See all channel/branch/worker activity
- **Manage memories**: Browse memory graph, create memories
- **Install skills**: Add capabilities from skills.sh registry
- **Schedule tasks**: Set up cron jobs
- **Monitor performance**: View metrics and logs

## Configuration Files

All data stored in:

```
/var/lib/spacebot/
├── config.toml          # Main configuration (auto-generated)
├── data/
│   ├── spacebot.db      # SQLite database
│   ├── secrets.redb     # Encrypted secrets
│   └── lance/           # Vector database
├── ingest/              # Drop files here to import
└── skills/              # Installed skills
```

You can edit `config.toml` to customize:

```bash
# Stop Spacebot first
sudo systemctl stop spacebot

# Edit config
sudo nano /var/lib/spacebot/config.toml

# Restart
sudo systemctl start spacebot
```

## Troubleshooting

### Bot Won't Start

```bash
# Check if AI Gateway is running
curl http://localhost:8080/health

# Check if LM Studio is running
curl http://localhost:1234/v1/models

# Check Spacebot logs
sudo journalctl -u spacebot -n 100
```

### Bot Not Responding in Discord

1. Verify bot token is correct:
   ```bash
   sudo cat /run/agenix/spacebot-discord-token
   ```

2. Check bot has **Message Content Intent** enabled in Discord Developer Portal

3. Check bot has permission to read/send messages in the channel

4. Check logs:
   ```bash
   sudo journalctl -u spacebot -f
   ```

### Container Restarting

```bash
# View restart count
systemctl show spacebot | grep RestartCount

# Check logs for crash reason
sudo journalctl -u spacebot -n 200 --no-pager
```

### Out of Memory

```bash
# Check memory usage
systemctl show spacebot | grep MemoryCurrent

# Increase memory limit in config.nix
services.spacebot.memory = "8G";  # Increase from 4G
```

## Next Steps

1. **Customize your agent**: Edit `/var/lib/spacebot/config.toml`
2. **Add more platforms**: Configure Slack or Telegram
3. **Install skills**: Browse https://skills.sh
4. **Set up cron jobs**: Schedule recurring tasks
5. **Configure routing**: Optimize model selection per task type

## Getting Help

- **Documentation**: https://docs.spacebot.sh
- **GitHub**: https://github.com/spacedriveapp/spacebot
- **Discord**: https://discord.gg/gTaF2Z44f5
- **Skills Registry**: https://skills.sh

## Removing Spacebot

If you need to uninstall:

```bash
# Stop and disable
sudo systemctl disable --now spacebot

# Remove container
podman rm -f spacebot

# Remove from config.nix
# Comment out or remove services.spacebot section

# Rebuild
sudo nixos-rebuild switch

# Optional: Remove data
# sudo rm -rf /var/lib/spacebot
```
