# Single host registry consumed by flake.nix and colmena.nix.
{
  zephyr = builtins.fromJSON (builtins.readFile ./metadata/zephyr.json);
  nexus = builtins.fromJSON (builtins.readFile ./metadata/nexus.json);
  forge = builtins.fromJSON (builtins.readFile ./metadata/forge.json);
  sentry = builtins.fromJSON (builtins.readFile ./metadata/sentry.json);
}
