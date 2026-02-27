# Age-encrypted secrets for NixOS
# All secrets are encrypted for all cluster nodes
let
  # Master age key (j_kro)
  masterKey = "age156wjyjhftr6yd57zh8yfuafpdfgftc3uwpx3hqgc568m980tsakq2s4jcp";

  # Age public keys from all cluster nodes
  # Each node's SSH host key is converted to an age public key
  # This allows any node to decrypt the secrets
  allHosts = [
    masterKey # j_kro (zephyr)
    "age1gswgrzlw7pmwucc4e9rmxcfy873nr89gj4wcrl259gpfvd5u6u6qw9r9zg" # zephyr (host)
    "age1v9d4x0r3f500tr73hdp5vseszzkacmrwjw78nfyjke3gq7qsu55qq769pv" # nexus (host)
    "age19sjd6ska90xxwyap4xvp83ne9mnkuf667reevmelcqltv0vtxurq3sj55y" # forge (host)
    "age1v8egldxu9g4ytmasxpkp0kkl5jvjmea7yk8wurmsyuskrzphs3nqrrslsq" # sentry (host)
  ];
in {
  # Mining (active)
  "mining-api-token".publicKeys = allHosts;

  # Exa API key (optional, for MCP servers)
  "exa-api-key".publicKeys = allHosts;

  # GitHub Actions runner token (self-hosted CI/CD)
  "github-actions-runner-token".publicKeys = allHosts;

  # Zhipu AI (GLM) API key for SpaceBot
  "zhipu-api-key".publicKeys = allHosts;

  # HuggingFace token for model downloads
  "hf-token".publicKeys = allHosts;

  # Cachix token for reverb-os cache (private binary cache)
  "cachix-token".publicKeys = allHosts;
}
