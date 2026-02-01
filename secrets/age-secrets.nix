{
  ...
}: {
  age.secrets = {
    # Mining API token for XMRig HTTP API
    "mining-api-token" = {
      file = ./mining-api-token.age;
    };

    # Mining wallet address
    "mining-wallet" = {
      file = ./mining-wallet.age;
    };

    # OpenClaw API Keys
    "anthropic-api-key" = {
      file = ./anthropic-api-key.age;
    };

    "openai-api-key" = {
      file = ./openai-api-key.age;
    };

    # OpenClaw environment file (contains all OpenClaw env vars)
    "openclaw-env" = {
      file = ./openclaw-env.age;
    };

    # MinIO cache credentials (AIStor on nexus)
    "minio-cache-credentials" = {
      file = ./minio-cache-credentials.age;
    };
  };
}
