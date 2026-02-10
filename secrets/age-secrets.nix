_: {
  age.secrets = {
    # Mining API token for XMRig HTTP API
    "mining-api-token" = {
      file = ./mining-api-token.age;
    };

    # Mining wallet address
    "mining-wallet" = {
      file = ./mining-wallet.age;
    };

    # API Keys
    "anthropic-api-key" = {
      file = ./anthropic-api-key.age;
    };

    "openai-api-key" = {
      file = ./openai-api-key.age;
    };

    # MinIO cache credentials for AIStor on nexus
    # IMPORTANT: You must create this secret file before enabling minio-cache
    # Run: agenix -e minio-cache-credentials.age
    # Format: MINIO_ACCESS_KEY=xxx
    #         MINIO_SECRET_KEY=yyy
    # "minio-cache-credentials" = {
    #   file = ./minio-cache-credentials.age;
    # };

    # Cachix authentication token (for pushing to reverb-os cache)
    # "cachix-token" = {
    #   file = ./cachix-token.age;
    # };

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
