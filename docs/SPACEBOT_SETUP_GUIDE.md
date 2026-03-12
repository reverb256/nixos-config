# Spacebot Setup Guide

Complete guide to deploying Spacebot on NixOS with Podman and integrating with your AI Gateway.

## Prerequisites

- ✅ Podman enabled (`services.podman.enable = true`)
- ✅ AI Gateway running on port 8080
- ✅ Agenix for secret management (optional but recommended)

## Quick Start

### Prerequisites

✅ You already have:
- NixOS with Flakes enabled
- AI Gateway running on port 8080
- LM Studio running on port 1234
- Agenix for secret management

### 1. Generate Discord Bot Token

**Option A: Use setup script**
```bash
/etc/nixos/scripts/setup-spacebot-token.sh
```

**Option B: Manual**
```bash
# Get your age public key
grep -oP 'public key: \K.*' /home/j_kro/.age/key.txt

# Encrypt your Discord bot token (replace YOUR_TOKEN)
echo "YOUR_DISCORD_BOT_TOKEN" | age -r YOUR_AGE_PUBLIC_KEY > /etc/nixos/secrets/spacebot-discord-token.age
```

### 2. Enable Podman and Spacebot

Add to your `/etc/nixos/hosts/zephyr/configuration.nix`:

```nix
{
  # Enable Podman
  services.podman.enable = true;

  # Enable Spacebot with Discord integration
  services.spacebot = {
    enable = true;

    # Use your existing AI Gateway
    useGateway = true;
    gatewayUrl = "http://127.0.0.1:8080";

    # Configure Discord (optional)
    discord.enable = true;
    discord.tokenFile = "/run/agenix/spacebot-discord-token";

    # Configure Slack (optional)
    # slack.enable = true;
    # slack.tokenFile = "/run/agenix/spacebot-slack-token";

    # Configure Telegram (optional)
    # telegram.enable = true;
    # telegram.tokenFile = "/run/agenix/spacebot-telegram-token";
  };
}
```

### 2. Create Secrets with Agenix

Generate agenix secrets for your bot tokens:

```bash
# Create Discord bot token secret
echo "YOUR_DISCORD_BOT_TOKEN" | age -r $(cat /home/j_kro/.age/key.txt | grep -oP 'public key: \K.*') > /etc/nixos/secrets/spacebot-discord-token.age

# Create Slack bot token secret (if using Slack)
echo "YOUR_SLACK_BOT_TOKEN" | age -r $(cat /home/j_kro/.age/key.txt | grep -oP 'public key: \K.*') > /etc/nixos/secrets/spacebot-slack-token.age

# Create Telegram bot token secret (if using Telegram)
echo "YOUR_TELEGRAM_BOT_TOKEN" | age -r $(cat /home/j_kro/.age/key.txt | grep -oP 'public key: \K.*') > /etc/nixos/secrets/spacebot-telegram-token.age
```

### 3. Add Secrets to NixOS Configuration

Add to your `configuration.nix` in the `age.secrets` section:

```nix
age.secrets.spacebot-discord-token = {
  file = "${inputs.self}/secrets/spacebot-discord-token.age";
  mode = "440";
  owner = "root";
  group = "root";
};

# Optional: Add Slack secret if using Slack
age.secrets.spacebot-slack-token = {
  file = "${inputs.self}/secrets/spacebot-slack-token.age";
  mode = "440";
  owner = "root";
  group = "root";
};

# Optional: Add Telegram secret if using Telegram
age.secrets.spacebot-telegram-token = {
  file = "${inputs.self}/secrets/spacebot-telegram-token.age";
  mode = "440";
  owner = "root";
  group = "root";
};
```

### 4. Build and Switch

```bash
# Rebuild NixOS configuration
sudo nixos-rebuild switch

# Start Spacebot
sudo systemctl start spacebot

# Check status
sudo systemctl status spacebot

# View logs
sudo journalctl -u spacebot -f
```

## Accessing Spacebot

### Web UI

Spacebot's web UI is available at:

```
http://localhost:19898
```

Access via Tailscale from other machines:

```
http://zephyr:19898
```

### CLI Management

```bash
# List containers
podman ps

# View logs
podman logs spacebot

# Execute commands in container
podman exec -it spacebot /bin/sh

# Restart container
sudo systemctl restart spacebot

# Stop container
sudo systemctl stop spacebot
```

## Configuration

### Auto-Generated Config

Spacebot automatically generates `config.toml` at:

```
/var/lib/spacebot/config.toml
```

You can edit this file to customize:

- Agent personality and behavior
- Model routing preferences
- Memory settings
- Cortex configuration
- Cron jobs
- Skills

### Manual Configuration

If you prefer to manage `config.toml` manually:

1. Stop Spacebot: `sudo systemctl stop spacebot`
2. Edit config: `sudo nano /var/lib/spacebot/config.toml`
3. Start Spacebot: `sudo systemctl start spacebot`

### Using Your AI Gateway

Spacebot is configured to use your AI Gateway by default:

```toml
[llm.provider.ai-gateway]
api_type = "openai_completions"
base_url = "http://127.0.0.1:8080/v1"

[defaults.routing]
channel = "magnum-opus-35b-a3b-i1"
worker = "magnum-opus-35b-a3b-i1"
```

This gives you:

- ✅ Automatic model routing
- ✅ Semantic caching
- ✅ RAG with Qdrant
- ✅ Rate limiting
- ✅ Metrics in Prometheus
- ✅ Fallback to ZAI/LM Studio

## Platform Setup

### Discord

1. Create a Discord application at https://discord.com/developers/applications
2. Create a bot user
3. Enable **Message Content Intent** and **Server Members Intent**
4. Copy the bot token
5. Invite bot to server with OAuth URL:
   ```
   https://discord.com/api/oauth2/authorize?client_id=YOUR_CLIENT_ID&permissions=8&scope=bot%20applications.commands
   ```

Required permissions:
- Read Messages/View Channels
- Send Messages
- Embed Links
- Attach Files
- Read Message History
- Add Reactions
- Use Slash Commands

### Slack

1. Create a Slack app at https://api.slack.com/apps
2. Enable **Socket Mode**
3. Add Bot Token Scopes:
   - `channels:history`
   - `channels:read`
   - `channels:write`
   - `chat:write`
   - `files:read`
   - `files:write`
   - `reactions:read`
   - `reactions:write`
4. Install app to workspace
5. Copy Bot Token (xoxb-...)

### Telegram

1. Message @BotFather on Telegram
2. Send `/newbot`
3. Follow prompts to create bot
4. Copy the API token
5. (Optional) Set description, about text, profile pic

## Data Persistence

All data is stored in `/var/lib/spacebot/`:

```
/var/lib/spacebot/
├── config.toml          # Main configuration
├── data/
│   ├── spacebot.db      # SQLite database (conversations, memories, cron)
│   ├── secrets.redb     # Encrypted secrets storage
│   └── lance/           # Vector database (embeddings)
├── ingest/              # Drop files here for automatic memory extraction
└── skills/              # Installed skills from skills.sh
```

### Backing Up Data

```bash
# Stop Spacebot
sudo systemctl stop spacebot

# Create backup
sudo tar -czf spacebot-backup-$(date +%Y%m%d).tar.gz /var/lib/spacebot

# Restart Spacebot
sudo systemctl start spacebot
```

### Restoring from Backup

```bash
# Stop Spacebot
sudo systemctl stop spacebot

# Restore backup
sudo tar -xzf spacebot-backup-YYYYMMDD.tar.gz -C /

# Fix permissions
sudo chown -R root:root /var/lib/spacebot
sudo chmod 700 /var/lib/spacebot

# Restart Spacebot
sudo systemctl start spacebot
```

## Monitoring

### Prometheus Metrics

Spacebot exposes metrics at `/metrics` (automatically scraped if monitoring is enabled):

```promql
# Spacebot request rate
rate(spacebot_requests_total[5m])

# Spacebot error rate
rate(spacebot_errors_total[5m])

# Active conversations
spacebot_active_conversations

# Memory usage
spacebot_memory_count
```

### Health Check

```bash
# Check if Spacebot is responding
curl http://localhost:19898/health
```

## Troubleshooting

### Container Won't Start

```bash
# Check logs
sudo journalctl -u spacebot -n 100

# Check Podman logs
podman logs spacebot

# Verify image was pulled
podman images | grep spacebot
```

### Can't Connect to Discord/Slack/Telegram

1. Verify bot token is correct
2. Check bot has required permissions/scopes
3. Check firewall allows outbound connections
4. View logs: `sudo journalctl -u spacebot -f`

### AI Gateway Issues

```bash
# Verify gateway is running
curl http://127.0.0.1:8080/health

# Check gateway logs
sudo journalctl -u ai-inference-gateway -f
```

### Memory Issues

Spacebot uses LanceDB for vector embeddings, which can grow over time.

```bash
# Check disk usage
sudo du -sh /var/lib/spacebot/*

# Prune old memories (via Spacebot UI or CLI)
# Or manually clean up old embeddings
```

## Advanced Configuration

### Custom Model Routing

Edit `/var/lib/spacebot/config.toml`:

```toml
[defaults.routing]
channel = "anthropic/claude-sonnet-4"
worker = "anthropic/claude-haiku-4.5"

[defaults.routing.task_overrides]
coding = "anthropic/claude-sonnet-4"
research = "anthropic/claude-opus-4"

[defaults.routing.prompt_routing]
enabled = true
process_types = ["channel", "branch"]
```

### Add Skills from skills.sh

```bash
# Via Spacebot web UI
# Or CLI (if you have CLI access)
sudo podman exec -it spacebot spacebot skill add vercel-labs/agent-skills
```

### Configure Cron Jobs

Via Spacebot web UI or edit config:

```toml
[[jobs]]
id = "daily-summary"
schedule = "0 9 * * *"  # 9 AM daily
agent_id = "default"
prompt = "Generate a daily summary of all conversations"
```

### Multi-Agent Setup

```toml
[[agents]]
id = "community-bot"
name = "Community Helper"
description = "Friendly assistant for community channels"

[[agents]]
id = "dev-assistant"
name = "Code Assistant"
description = "Technical help for development"

[[bindings]]
agent_id = "community-bot"
channel = "discord"
guild_id = "COMMUNITY_GUILD_ID"

[[bindings]]
agent_id = "dev-assistant"
channel = "slack"
```

## Resources

- **Documentation**: https://docs.spacebot.sh
- **GitHub**: https://github.com/spacedriveapp/spacebot
- **Discord**: https://discord.gg/gTaF2Z44f5
- **Skills Registry**: https://skills.sh

## Agent Federation (j-kro's Personal Setup)

As of 2026-03-09, j-kro's Spacebot instance runs a 7-agent federation:

1. **Flow** (hub) - Personal assistant, coordinates all agents
2. **Infra** - NixOS, mining cluster, deployments
3. **Dev** - Coding, debugging, feature development
4. **Business** - Client comms, billing, project status
5. **Agency** - Client portfolio manager
6. **DevOps** - Deep technical/architectural work
7. **TrovesAndCoves** - Robin's business assistant

All agents accessible via Telegram bot or Web UI at http://localhost:19898.
Default routing goes through Flow; use @agent_name for direct addressing.

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
