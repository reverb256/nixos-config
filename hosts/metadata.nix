# Informational host metadata mirror. Active Colmena deployment fields are
# derived from flake.nix's `hosts` attrset; keep this registry synchronized.
{
  zephyr = builtins.fromJSON (builtins.readFile ./metadata/zephyr.json);
  nexus = builtins.fromJSON (builtins.readFile ./metadata/nexus.json);
  forge = builtins.fromJSON (builtins.readFile ./metadata/forge.json);
  sentry = builtins.fromJSON (builtins.readFile ./metadata/sentry.json);
}
