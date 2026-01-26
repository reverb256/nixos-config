# Age-encrypted secrets for NixOS
# Public key for zephyr host
{
  # Host public keys for all systems
  "zephyr-host" = "age175jstqazl7sj20xzuhc4l9qn0xt0ag0nvh2paxkk6veav95se4ysjua4e5";
  "nexus-host" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEldBvJIZYJKHw8pt0/Bx3xhJK4rSrhno0NyHgTtWAaV";
  "forge-host" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFf1b4QFWOV8OI2zC3N6rlE2sHHRzcPGfS7wr/VSoanr";
  "sentry-host" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBK7IznKNG8BJVrPv1dnJBrbFhcmzTKaYSAzVdrXV7Fn";

  # List of all secret files to encrypt with agenix
  secrets = {
    # Claude Code API Key (KAT/StreamLake)
    "claude-api-key.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];

    # Clawdbot - StreamLake (KAT-Coder-Pro-v1)
    "clawdbot-streamlake.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];

    # Clawdbot - OpenRouter (fallback)
    "clawdbot-openrouter.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];

    # Clawdbot - Anthropic (Claude)
    "clawdbot-anthropic.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];

    # Clawdbot - OpenAI
    "clawdbot-openai.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];

    # Clawdbot - GLM (Zhipu)
    "clawdbot-glm.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];

    # Clawdbot - AWS Bedrock Access Key
    "clawdbot-bedrock-access.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];

    # Clawdbot - AWS Bedrock Secret Key
    "clawdbot-bedrock-secret.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];

    # Hugging Face API Token
    "hf-token.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];

    # Clawdbot - ElevenLabs (TTS)
    "clawdbot-elevenlabs.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];

    # Clawdbot - Gateway Password
    "clawdbot-gateway-password.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];

    # Messaging Platform Tokens (placeholders for future use)
    "clawdbot-whatsapp.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];
    "clawdbot-telegram.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];
    "clawdbot-discord.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];
    "clawdbot-slack.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];
    "clawdbot-msteams-id.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];
    "clawdbot-msteams-password.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];
    "clawdbot-matrix.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];
  };
}
