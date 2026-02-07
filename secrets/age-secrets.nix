{lib, ...}: {
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

    # OpenClaw Gateway Token (separate from env file for container configs)
    # SECURITY FIX: Moved from hardcoded "dev-token-12345" to agenix secret
    "openclaw-gateway-token" = {
      file = ./openclaw-gateway-token.age;
    };

    # MinIO cache credentials for AIStor on nexus
    # IMPORTANT: You must create this secret file before enabling openclaw-storage
    # Run: agenix -e minio-cache-credentials.age
    # Format: MINIO_ACCESS_KEY=xxx
    #         MINIO_SECRET_KEY=yyy
    # "minio-cache-credentials" = {
    #   file = ./minio-cache-credentials.age;
    # };

    # Cachix authentication token (for pushing to reverb-os cache)
    "cachix-token" = {
      file = ./cachix-token.age;
    };

    # Garnix cache credentials (for fetching from private Garnix cache)
    "garnix-netrc" = {
      file = ./garnix-netrc.age;
    };

    # Grafana password for monitoring dashboard
    # SECURITY FIX: Removed default "changeme" password, now requires explicit secret
    "grafana-password" = {
      file = ./grafana-password.age;
    };
  };
}
