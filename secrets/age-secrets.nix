{
  config,
  lib,
  pkgs,
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

    # Molt.bot API keys
    "moltbot-openrouter-key" = {
      file = ./moltbot-openrouter-key.age;
    };

    "moltbot-kilocode-key" = {
      file = ./moltbot-kilocode-key.age;
    };

    "moltbot-anthropic-key" = {
      file = ./moltbot-anthropic-key.age;
    };
  };
}
