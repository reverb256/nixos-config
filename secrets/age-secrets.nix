{config, ...}: {
  age.secrets = {
    # Mining API token for XMRig HTTP API (internal stats/pause/resume)
    "mining-api-token" = {
      file = ./mining-api-token.age;
      owner = "mining";
      group = "mining";
      mode = "400";
    };

    # OpenClaw Gateway authentication token
    "openclaw-token" = {
      file = ./openclaw-token.age;
      owner = "j_kro";
      group = "users";
      mode = "400";
    };

    # MCP Servers Exa API key
    "exa-api-key" = {
      file = ./exa-api-key.age;
      owner = "j_kro";
      group = "users";
      mode = "400";
    };
  };
}
