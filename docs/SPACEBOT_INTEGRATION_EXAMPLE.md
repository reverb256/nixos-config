# Example: Adding Spacebot to Your Configuration

Complete example of integrating Spacebot into your existing NixOS configuration.

## Add to `/etc/nixos/hosts/zephyr/configuration.nix`

Add this in your host configuration file, alongside your existing services:

```nix
# ============================================================================
# PODMAN - Container Runtime for Spacebot
# ============================================================================
services.podman = {
  enable = true;
  dockerCompat = true;  # Creates `docker` alias for compatibility
  compose = true;       # Install podman-compose
  rootless = true;      # Run containers without root
};

# ============================================================================
# SPACEBOT - AI Agent for Teams
# ============================================================================
services.spacebot = {
  enable = true;

  # Integration with your existing AI Gateway
  useGateway = true;
  gatewayUrl = "http://127.0.0.1:8080";

  # Web UI configuration
  host = "127.0.0.1";
  port = 19898;

  # Discord integration (recommended for start)
  discord = {
    enable = true;
    # Use agenix secret (recommended)
    tokenFile = "/run/agenix/spacebot-discord-token";
    # Or use direct token (not recommended)
    # token = "your_discord_bot_token_here";
    guildId = "YOUR_GUILD_ID";  # Optional: restrict to specific server
  };

  # Optional: Slack integration
  # slack = {
  #   enable = true;
  #   tokenFile = "/run/agenix/spacebot-slack-token";
  # };

  # Optional: Telegram integration
  # telegram = {
  #   enable = true;
  #   tokenFile = "/run/agenix/spacebot-telegram-token";
  # };

  # Resource limits
  memory = "4G";
  cpu = "2";
};
```

## Add Agenix Secrets

Add to your existing `age.secrets` section in `/etc/nixos/hosts/zephyr/configuration.nix`:

```nix
# ============================================================================
# AGENIX SECRETS - Spacebot Bot Tokens
# ============================================================================
age.secrets.spacebot-discord-token = {
  file = "${inputs.self}/secrets/spacebot-discord-token.age";
  mode = "440";
  owner = "root";
  group = "root";
};

# Optional: Add Slack token secret
# age.secrets.spacebot-slack-token = {
#   file = "${inputs.self}/secrets/spacebot-slack-token.age";
#   mode = "440";
#   owner = "root";
#   group = "root";
# };

# Optional: Add Telegram token secret
# age.secrets.spacebot-telegram-token = {
#   file = "${inputs.self}/secrets/spacebot-telegram-token.age";
#   mode = "440";
#   owner = "root";
#   group = "root";
# };
```

## Add Firewall Exception

Your existing firewall configuration already has port 8080 open. Spacebot needs port 19898:

```nix
networking.firewall = {
  allowedTCPPorts = [
    # ... existing ports ...
    9757    # WiVRn
    18789   # Steam Remote Play
    19898   # Spacebot Web UI (ADD THIS LINE)
  ];
};
```

## Generate Secrets

Generate the bot token secrets:

```bash
# Discord bot token
echo "YOUR_DISCORD_BOT_TOKEN_HERE" | \
  age -r $(cat /home/j_kro/.age/key.txt | grep -oP 'public key: \K.*') \
  > /etc/nixos/secrets/spacebot-discord-token.age

# (Optional) Slack bot token
# echo "YOUR_SLACK_BOT_TOKEN_HERE" | \
#   age -r $(cat /home/j_kro/.age/key.txt | grep -oP 'public key: \K.*') \
#   > /etc/nixos/secrets/spacebot-slack-token.age

# (Optional) Telegram bot token
# echo "YOUR_TELEGRAM_BOT_TOKEN_HERE" | \
#   age -r $(cat /home/j_kro/.age/key.txt | grep -oP 'public key: \K.*') \
#   > /etc/nixos/secrets/spacebot-telegram-token.age
```

## Deploy

```bash
# Rebuild and switch
sudo nixos-rebuild switch

# Enable and start Spacebot
sudo systemctl enable spacebot
sudo systemctl start spacebot

# Check status
sudo systemctl status spacebot

# View logs
sudo journalctl -u spacebot -f
```

## Verify

Test that everything is working:

```bash
# Check Podman is running
podman ps

# Check Spacebot container is running
podman ps | grep spacebot

# Check Spacebot web UI is accessible
curl http://localhost:19898

# Check AI Gateway integration
curl http://localhost:19898/health | jq .
```

## Access

- **Web UI**: http://localhost:19898
- **Via Tailscale**: http://zephyr:19898

## Getting Bot Tokens

### Discord Token

1. Go to https://discord.com/developers/applications
2. Create a new application
3. Go to "Bot" section
4. Click "Add Bot"
5. Copy the token (click "Reset Token" to reveal)
6. Enable Privileged Gateway Intents:
   - Message Content Intent
   - Server Members Intent

### Slack Token

1. Go to https://api.slack.com/apps
2. Create New App → From scratch
3. Add "Socket Mode"
4. Install to workspace
5. Copy Bot User OAuth Token (starts with `xoxb-`)

### Telegram Token

1. Open Telegram
2. Search for @BotFather
3. Send `/newbot`
4. Follow prompts
5. Copy the API token provided

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Zephyr (NixOS)                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐         ┌──────────────┐                  │
│  │   Discord    │         │   Spacebot   │                  │
│  │  Platform    │◄────────│   Container  │                  │
│  └──────────────┘         │   (Podman)   │                  │
│                            └──────┬───────┘                  │
│                                   │                           │
│                                   ▼                           │
│                            ┌──────────────┐                  │
│                            │ AI Gateway   │                  │
│                            │  (Port 8080) │                  │
│                            └──────┬───────┘                  │
│                                   │                           │
│                                   ▼                           │
│                            ┌──────────────┐                  │
│                            │ LM Studio    │                  │
│                            │  (Port 1234) │                  │
│                            └──────────────┘                  │
│                                                               │
│  Supporting Services:                                         │
│  - Qdrant (Vector DB)                                         │
│  - Redis (Caching)                                            │
│  - Prometheus (Metrics)                                       │
└─────────────────────────────────────────────────────────────┘
```

## Benefits of This Setup

✅ **Declarative**: Everything managed via NixOS configuration
✅ **Integrated**: Uses your existing AI Gateway with routing, caching, RAG
✅ **Secure**: Bot tokens managed with agenix encryption
✅ **Monitorable**: Metrics exposed to Prometheus
✅ **Isolated**: Runs in Podman container with resource limits
✅ **Persistent**: Data stored in `/var/lib/spacebot`
✅ **Scalable**: Easy to add more agents or messaging platforms

## Next Steps

1. Configure Discord bot permissions
2. Invite bot to your Discord server
3. Test basic conversation
4. Explore Spacebot web UI
5. Customize agent personality in config
6. Add skills from skills.sh registry
7. Set up cron jobs for recurring tasks
8. Configure memory graph preferences
