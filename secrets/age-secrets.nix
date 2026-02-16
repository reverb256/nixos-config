{...}: {
  age.secrets = {
    # Mining API token for XMRig HTTP API (internal stats/pause/resume)
    # NOTE: Temporarily disabled - age identity not available on forge
    # Re-enable when xmrig is actually used and identity is properly configured
    # "mining-api-token" = {
    #   file = ./mining-api-token.age;
    #   owner = "mining";
    #   group = "mining";
    #   mode = "400";
    # };



    # MCP Servers Exa API key
    "exa-api-key" = {
      file = ./exa-api-key.age;
      owner = "j_kro";
      group = "users";
      mode = "400";
    };
  };
}
