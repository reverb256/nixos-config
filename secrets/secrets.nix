# Age-encrypted secrets for NixOS
# All secrets are encrypted for all hosts
let
  allHosts = [
    "age175jstqazl7sj20xzuhc4l9qn0xt0ag0nvh2paxkk6veav95se4ysjua4e5" # zephyr
    "age19r77h4d3d93fla0ptc4zu3yvdxhvykdusd23c5wmrmzut55rn96qk0kc3n" # nexus
    "age1chus24x5vg85993trehnms4gndw9e7qm0m3z5q65997c8az7rf6svffh4w" # forge
    "age14duc9p3yrmelfjd94tfkzgenpfcfarucn3ax6ygl0w4erh9p0ddqr674ly" # sentry
  ];
in {
  # Claude Code API Key (KAT/StreamLake)
  "claude-api-key.age".publicKeys = allHosts;

  # Clawdbot - StreamLake (KAT-Coder-Pro-v1)
  "clawdbot-streamlake.age".publicKeys = allHosts;

  # Clawdbot - OpenRouter (fallback)
  "clawdbot-openrouter.age".publicKeys = allHosts;

  # Clawdbot - Anthropic (Claude)
  "clawdbot-anthropic.age".publicKeys = allHosts;

  # Clawdbot - OpenAI
  "clawdbot-openai.age".publicKeys = allHosts;

  # Clawdbot - GLM (Zhipu)
  "clawdbot-glm.age".publicKeys = allHosts;

  # Clawdbot - AWS Bedrock Access Key
  "clawdbot-bedrock-access.age".publicKeys = allHosts;

  # Clawdbot - AWS Bedrock Secret Key
  "clawdbot-bedrock-secret.age".publicKeys = allHosts;

  # Hugging Face API Token
  "hf-token.age".publicKeys = allHosts;

  # Clawdbot - ElevenLabs (TTS)
  "clawdbot-elevenlabs.age".publicKeys = allHosts;

  # Clawdbot - Gateway Password
  "clawdbot-gateway-password.age".publicKeys = allHosts;

  # Messaging Platform Tokens (placeholders for future use)
  "clawdbot-whatsapp.age".publicKeys = allHosts;
  "clawdbot-telegram.age".publicKeys = allHosts;
  "clawdbot-discord.age".publicKeys = allHosts;
  "clawdbot-slack.age".publicKeys = allHosts;
  "clawdbot-msteams-id.age".publicKeys = allHosts;
  "clawdbot-msteams-password.age".publicKeys = allHosts;
  "clawdbot-matrix.age".publicKeys = allHosts;
}
