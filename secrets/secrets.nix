# Age-encrypted secrets for NixOS
# All secrets are encrypted for all hosts
let
  allHosts = [
    "age1g4d90gk5qpzhw0urvmmdfzy8xl4ffqvk4f4ryv7qzwfmgm75lf0qtzqyqq" # zephyr (from SSH ed25519)
  ];
in {
  # Claude Code API Key (KAT/StreamLake)
  "claude-api-key".publicKeys = allHosts;

  # Hugging Face API Token
  "hf-token".publicKeys = allHosts;

  # Mining API token for XMRig HTTP API
  "mining-api-token".publicKeys = allHosts;

  # Mining wallet addresses (encrypted)
  "mining-wallet".publicKeys = allHosts;

  # OpenClaw API Keys
  "anthropic-api-key".publicKeys = allHosts;
  "openai-api-key".publicKeys = allHosts;
  "openclaw-env".publicKeys = allHosts;

  # OpenClaw Gateway Token (SECURITY FIX: Separate from env file for container configs)
  "openclaw-gateway-token".publicKeys = allHosts;

  # MinIO cache credentials for AIStor on nexus
  # TODO: Uncomment after encrypting with real credentials:
  # See AISTOR-DEPLOY.md for instructions
  # "minio-cache-credentials".publicKeys = allHosts;

  # Garnix cache credentials
  "garnix-netrc".publicKeys = allHosts;
}
