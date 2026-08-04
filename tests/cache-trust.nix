{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;

  registry = import ../modules/system/nix-cache-registry.nix;
  nixConfig = builtins.readFile ../modules/system/nix-config.nix;
  distributedBuilds = builtins.readFile ../modules/system/distributed-builds.nix;

  has = needle: source: lib.strings.hasInfix needle source;
  noWildcardTrustedUser =
    !(has ''trusted-users = lib.mkForce [
        "root"
        "*"'' distributedBuilds);
  signatureVerificationDeferred = has "require-sigs = lib.mkForce false" distributedBuilds;
  flakeConfigNotAccepted = has "accept-flake-config = false" nixConfig;
  registryHasLocalKey = builtins.elem registry.local.publicKey registry.trustedPublicKeys;
  registryHasLocalEndpoint =
    builtins.any (substituter: has registry.local.endpoint substituter) registry.substituters;
  registryHasSignedCaches =
    builtins.all (key: lib.strings.hasInfix ":" key) registry.trustedPublicKeys;
  niriCachePreserved = builtins.any (substituter: has "niri.cachix.org" substituter) registry.substituters;
  noctaliaCachePreserved = builtins.any (substituter: has "noctalia.cachix.org" substituter) registry.substituters;
  niriKeyRegistered = builtins.any (key: has "niri.cachix.org-1:" key) registry.trustedPublicKeys;
  noctaliaKeyRegistered = builtins.any (key: has "noctalia.cachix.org-1:" key) registry.trustedPublicKeys;

  checks = {
    no_wildcard_trusted_user = noWildcardTrustedUser;
    signature_verification_followup_is_explicit = signatureVerificationDeferred;
    flake_config_not_accepted = flakeConfigNotAccepted;
    local_cache_key_registered = registryHasLocalKey;
    local_cache_endpoint_registered = registryHasLocalEndpoint;
    trusted_keys_have_key_separator = registryHasSignedCaches;
    niri_cache_preserved = niriCachePreserved;
    noctalia_cache_preserved = noctaliaCachePreserved;
    niri_key_registered = niriKeyRegistered;
    noctalia_key_registered = noctaliaKeyRegistered;
  };
  failures = lib.filterAttrs (_: value: !value) checks;
  failureNames = builtins.attrNames failures;
in {
  inherit checks;
  failures = failureNames;
  passed = failureNames == [];
}
