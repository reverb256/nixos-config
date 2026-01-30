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

    # OpenClaw Telegram bot token
    "openclaw-telegram-token" = {
      file = ./openclaw-telegram-token.age;
      mode = "0600";
    };
  };
}
