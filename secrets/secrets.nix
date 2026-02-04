# Age-encrypted secrets for NixOS
# All secrets are encrypted for all hosts
let
  allHosts = [
    "age1pn55e68h5twm8ksrm29pzf4w5t8twdznmy0sqg5gvk094punpctq06q8zn" # zephyr (from age-keygen)
  ];
in {
  "claude-api-key".publicKeys = allHosts;
  "hf-token".publicKeys = allHosts;
  "mining-api-token".publicKeys = allHosts;
  "mining-wallet".publicKeys = allHosts;
  "anthropic-api-key".publicKeys = allHosts;
  "openai-api-key".publicKeys = allHosts;
  "openclaw-env".publicKeys = allHosts;
  "openclaw-gateway-token".publicKeys = allHosts;
  "garnix-netrc".publicKeys = allHosts;
}
