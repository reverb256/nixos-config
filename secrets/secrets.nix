# Age-encrypted secrets for NixOS
# All secrets are encrypted for all hosts
let
  allHosts = [
    "age175jstqazl7sj20xzuhc4l9qn0xt0ag0nvh2paxkk6veav95se4ysjua4e5" # zephyr
    "age19r77h4d3d93fla0ptc4zu3yvdxhvykdusd23c5wmrmzut55rn96qk0kc3n" # nexus
    "age1chus24x5vg85993trehnms4gndw9e7qm0m3z5q65997c8az7rf6svffh4w" # forge
    "age14duc9p3yrmelfjd94tfkzgenpfcfarucn3ax6ygl0w4erh9p0ddqr674ly" # sentry
  ];
in {
  # Claude Code API Key (KAT/StreamLake)
  "claude-api-key".publicKeys = allHosts;

  # Hugging Face API Token
  "hf-token".publicKeys = allHosts;
}
