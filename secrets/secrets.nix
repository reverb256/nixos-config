# Age-encrypted secrets for NixOS
# All secrets are encrypted for all hosts
let
  # Public key from /home/j_kro/.config/sops/age/keys.txt
  allHosts = [
    "age1edmwffffyz5m9wtf0mhfeh002h0ftrwk8luumkl89hyycr47r30qalg29y" # zephyr (j_kro)
  ];
in {
  # Mining (active)
  "mining-api-token".publicKeys = allHosts;



  # Exa API key (optional, for MCP servers)
  "exa-api-key".publicKeys = allHosts;
}
