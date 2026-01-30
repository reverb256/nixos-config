# Molt.bot Secrets Setup

This directory contains age-encrypted secrets for Molt.bot AI agent.

## Required Secrets

1. **moltbot-openrouter-key** - OpenRouter API key (recommended, has free tier)
2. **moltbot-kilocode-key** - Kilo.ai API key (optional, for free models)
3. **moltbot-anthropic-key** - Anthropic API key (optional, for paid Claude)

## Setup Instructions

### 1. Create the secret files

```bash
# For OpenRouter (get key from https://openrouter.ai/keys)
echo "sk-or-v1-..." > /tmp/moltbot-openrouter-key
agenix -e secrets/moltbot-openrouter-key.age < /tmp/moltbot-openrouter-key
rm /tmp/moltbot-openrouter-key

# For Kilo.ai (optional)
echo "kilocode-..." > /tmp/moltbot-kilocode-key
agenix -e secrets/moltbot-kilocode-key.age < /tmp/moltbot-kilocode-key
rm /tmp/moltbot-kilocode-key

# For Anthropic (optional)
echo "sk-ant-..." > /tmp/moltbot-anthropic-key
agenix -e secrets/moltbot-anthropic-key.age < /tmp/moltbot-anthropic-key
rm /tmp/moltbot-anthropic-key
```

### 2. Rebuild NixOS

```bash
just switch
# or
sudo nixos-rebuild switch --flake .#zephyr
```

### 3. Initialize Molt.bot

```bash
# Run setup wizard
moltbot onboard --install-daemon

# Or start gateway manually
moltbot gateway --port 18789 --verbose
```

## Model Providers

### OpenRouter (Recommended - Free Tier)
- URL: https://openrouter.ai/
- Free models available with rate limits
- Supports many providers through single API

### Kilo.ai (Free Models)
- URL: https://kilocode.ai/
- Free tier with minimax-m2.1 model
- Good for testing

### LM Studio (Local)
- Run models locally on your RTX 3090
- No API key needed
- Set `services.moltbot.lmStudioUrl = "http://localhost:1234/v1"`

### Anthropic Claude (Paid)
- Most capable models
- Requires paid subscription
- Set `services.moltbot.defaultProvider = "anthropic"`

## Configuration

Edit `hosts/zephyr/configuration.nix` to change provider:

```nix
services.moltbot = {
  enable = true;
  defaultProvider = "openrouter"; # or "kilocode", "lmstudio", "anthropic"
  openrouterApiKeyFile = config.age.secrets.moltbot-openrouter-key.path;
  # Optional: kilocodeApiKeyFile = config.age.secrets.moltbot-kilocode-key.path;
  # Optional: lmStudioUrl = "http://localhost:1234/v1";
};
```

## Documentation

- Molt.bot: https://molt.bot
- Docs: https://docs.molt.bot
- GitHub: https://github.com/moltbot/moltbot
