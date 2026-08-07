{pkgs ? import <nixpkgs> {}}:
let
  inherit (pkgs) lib;
  policy = import ../contracts/cache-policy.nix;
  nixConfigSource = builtins.readFile ../modules/system/nix-config.nix;
  distributedSource = builtins.readFile ../modules/system/distributed-builds.nix;
  requiredCaches = [
    "https://cache.nixos.org"
    "https://cache.nixos-cuda.org"
    "https://nix-community.cachix.org"
    "https://reverb-os.cachix.org"
  ];
  requiredKeys = [
    "cache.nixos.org-1:"
    "cache.nixos-cuda.org-1:"
    "nix-community.cachix.org-1:"
    "reverb-os.cachix.org-1:"
  ];
  cachePolicyShape =
    builtins.isAttrs policy
    && builtins.isList policy.substituters
    && builtins.isList policy.trustedPublicKeys
    && builtins.isList policy.intentionalCustomPackages
    && builtins.isAttrs policy.specializedCaches;
  requiredCachesDeclared = builtins.all (
    url: builtins.any (configured: lib.strings.hasInfix url configured) policy.substituters
  ) requiredCaches;
  nixConfigUsesPolicy =
    lib.strings.hasInfix "cachePolicy.substituters" nixConfigSource
    && lib.strings.hasInfix "cachePolicy.trustedPublicKeys" nixConfigSource;
  distributedUsesPolicy =
    lib.strings.hasInfix "cachePolicy.substituters" distributedSource
    && lib.strings.hasInfix "cachePolicy.trustedPublicKeys" distributedSource;
  signaturesRequired =
    lib.strings.hasInfix "require-sigs = lib.mkForce true" nixConfigSource
    && lib.strings.hasInfix "require-sigs = lib.mkForce true" distributedSource;
  requiredKeysDeclared = builtins.all (prefix: builtins.any (key: lib.strings.hasInfix prefix key) policy.trustedPublicKeys) requiredKeys;
  allSubstitutersUnique = lib.length (lib.unique policy.substituters) == lib.length policy.substituters;
  allTrustedKeysUnique = lib.length (lib.unique policy.trustedPublicKeys) == lib.length policy.trustedPublicKeys;
  publicCacheKeysPresent = builtins.all (
    cache:
      let host = builtins.head (lib.splitString "?" (builtins.substring 8 1000 cache));
      in builtins.any (key: lib.strings.hasInfix host key) policy.trustedPublicKeys
  ) (lib.filter (cache: lib.strings.hasPrefix "https://" cache) policy.substituters);
  customNamesUnique = lib.length (lib.unique policy.intentionalCustomPackages) == lib.length policy.intentionalCustomPackages;
  allCustomNamesNonEmpty = builtins.all (name: name != "") policy.intentionalCustomPackages;
  checks = {
    inherit cachePolicyShape requiredCachesDeclared nixConfigUsesPolicy distributedUsesPolicy signaturesRequired requiredKeysDeclared allSubstitutersUnique allTrustedKeysUnique publicCacheKeysPresent customNamesUnique allCustomNamesNonEmpty;
  };
  failures = builtins.attrNames (lib.filterAttrs (_: value: !value) checks);
in {
  inherit checks failures;
  passed = failures == [];
}
