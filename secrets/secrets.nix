# Age-encrypted secrets for NixOS
# All secrets are encrypted for all hosts
let
  allHosts = [
    "age1544cpynykxrv2upsnu7xyf4heyk0gsqmk39p8pkm2swdrssxnunq0cjux9" # zephyr (current)
    # Other hosts can be added here when their keys are available
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

  # MinIO cache credentials for AIStor on nexus
  # TODO: Uncomment after encrypting with real credentials:
  # See AISTOR-DEPLOY.md for instructions
  # "minio-cache-credentials".publicKeys = allHosts;

  # Garnix cache credentials
  "garnix-netrc".publicKeys = allHosts;
}
