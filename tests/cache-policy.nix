{pkgs ? import <nixpkgs> {}}:
let
  inherit (pkgs) lib;
  policy = import ../contracts/cache-policy.nix;
  nixConfigSource = builtins.readFile ../modules/system/nix-config.nix;
  distributedSource = builtins.readFile ../modules/system/distributed-builds.nix;
  effectiveSystem = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      ({ ... }: {
        boot.isContainer = true;
        networking.hostName = "cache-policy-test";
        system.stateVersion = "25.11";
        users.users.j_kro.home = "/home/j_kro";
      })
      ../modules/system/nix-config.nix
      ../modules/system/distributed-builds.nix
    ];
  };
  effectiveSettings = effectiveSystem.config.nix.settings;
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
    "zephyr-cache-1:"
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
  trustedUsersNoWildcard =
    effectiveSettings.trusted-users == [ "root" "j_kro" ]
    && !builtins.elem "*" effectiveSettings.trusted-users;
  flakeConfigNotAccepted =
    (lib.strings.hasInfix "accept-flake-config = false" nixConfigSource
      || lib.strings.hasInfix "accept-flake-config = lib.mkForce false" nixConfigSource)
    && !lib.strings.hasInfix "accept-flake-config = true" nixConfigSource;
  requiredKeysDeclared = builtins.all (prefix: builtins.any (key: lib.strings.hasInfix prefix key) policy.trustedPublicKeys) requiredKeys;
  allSubstitutersUnique = lib.length (lib.unique policy.substituters) == lib.length policy.substituters;
  allTrustedKeysUnique = lib.length (lib.unique policy.trustedPublicKeys) == lib.length policy.trustedPublicKeys;
  cacheEndpointKeyMapping = [
    { host = "cache.nixos.org"; keyPrefix = "cache.nixos.org-1:"; }
    { host = "cache.nixos-cuda.org"; keyPrefix = "cache.nixos-cuda.org-1:"; }
    { host = "nix-community.cachix.org"; keyPrefix = "nix-community.cachix.org-1:"; }
    { host = "niri.cachix.org"; keyPrefix = "niri.cachix.org-1:"; }
    { host = "noctalia.cachix.org"; keyPrefix = "noctalia.cachix.org-1:"; }
    { host = "nix-gaming.cachix.org"; keyPrefix = "nix-gaming.cachix.org-1:"; }
    { host = "ezkea.cachix.org"; keyPrefix = "ezkea.cachix.org-1:"; }
    { host = "maplespike.cachix.org"; keyPrefix = "maplespike.cachix.org-1:"; }
    { host = "reverb-os.cachix.org"; keyPrefix = "reverb-os.cachix.org-1:"; }
    { host = "10.1.1.110:50000"; keyPrefix = "zephyr-cache-1:"; }
  ];
  publicCacheKeysPresent = builtins.all ({ host, keyPrefix }:
    builtins.any (
      key: lib.strings.hasInfix keyPrefix key
        && (host == "10.1.1.110:50000" || lib.strings.hasInfix host key)
    ) policy.trustedPublicKeys
  ) cacheEndpointKeyMapping;
  effectiveTrustSettings =
    effectiveSettings.trusted-users == ["root" "j_kro"]
    && effectiveSettings.accept-flake-config == false
    && effectiveSettings.require-sigs == true;
  localCacheKeyExact =
    builtins.elem "http://10.1.1.110:50000?priority=90&want-mass-query=true" policy.substituters
    && builtins.elem "zephyr-cache-1:rDatmGO1sjYLUYCPxA3OAdkb88LmJdJiCy1DFtwftWU=" policy.trustedPublicKeys;
  customNamesUnique = lib.length (lib.unique policy.intentionalCustomPackages) == lib.length policy.intentionalCustomPackages;
  allCustomNamesNonEmpty = builtins.all (name: name != "") policy.intentionalCustomPackages;
  checks = {
    inherit cachePolicyShape requiredCachesDeclared nixConfigUsesPolicy distributedUsesPolicy signaturesRequired trustedUsersNoWildcard flakeConfigNotAccepted requiredKeysDeclared allSubstitutersUnique allTrustedKeysUnique publicCacheKeysPresent localCacheKeyExact effectiveTrustSettings customNamesUnique allCustomNamesNonEmpty;
  };
  failures = builtins.attrNames (lib.filterAttrs (_: value: !value) checks);
in {
  inherit checks failures;
  passed = failures == [];
}
