# Age-encrypted secrets for NixOS
# All secrets are encrypted for all hosts
let
  allHosts = [
    "age1dc2jhy8h860rga7yjv96vy6rg4jzd364gahj64gc9narr2gayc8q27rfgu" # generated 2026-02-06
  ];
in {
  "anthropic-api-key".publicKeys = allHosts;
  "openai-api-key".publicKeys = allHosts;
}
