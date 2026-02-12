_: {
  age.secrets = {
    # Mining API token for XMRig HTTP API (internal stats/pause/resume)
    "mining-api-token" = {
      file = ./mining-api-token.age;
      owner = "mining";
      group = "mining";
      mode = "400";
    };

    # Other secrets can be added as needed
    # To create: agenix -e /etc/nixos/secrets/<name>.age
    # Then add entry here and in secrets.nix
  };
}
