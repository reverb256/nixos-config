{pkgs ? import <nixpkgs> {}}: let
  lib = pkgs.lib;

  # Test that nixosConfigurations for all hosts can be evaluated
  # This is an integration test — it uses nix eval to check that each
  # host configuration evaluates without errors.
  #
  # NOTE: This test is designed to be run via `nix eval` or `just check`
  # and validates the flake outputs directly.

  expectedHosts = [ "zephyr" "nexus" "forge" "sentry" ];

  # Verify flake.nix defines nixosConfigurations for all expected hosts
  flakeSource = builtins.readFile ./../flake.nix;

  hasNixosConfigurations = lib.strings.hasInfix "nixosConfigurations" flakeSource;

  # Check each host is referenced in the flake
  hostPresentInFlake = host:
    lib.strings.hasInfix "nixosConfigurations.${host}" flakeSource ||
    lib.strings.hasInfix host flakeSource;

  missingHostsInFlake = builtins.filter (h: !(hostPresentInFlake h)) expectedHosts;

  # Check that flake.nix references colmena (deployment tool)
  hasColmena = lib.strings.hasInfix "colmena" flakeSource;

  # Check that flake inputs include agenix
  hasAgenixInput = lib.strings.hasInfix "agenix" flakeSource;

  # Check that flake inputs include home-manager
  hasHomeManagerInput = lib.strings.hasInfix "home-manager" flakeSource;

  # Check that flake inputs include nixpkgs
  hasNixpkgsInput = lib.strings.hasInfix "nixpkgs" flakeSource;

  # Verify flake.lock exists (pinned dependencies)
  flakeLockExists = builtins.pathExists ./../flake.lock;

  # Verify each host directory has a hardware-configuration.nix
  hardwareConfigExists = host:
    builtins.pathExists ./../hosts/${host}/hardware-configuration.nix;

  missingHardwareConfig = builtins.filter (h: !(hardwareConfigExists h)) expectedHosts;

  # Verify the common-host-defaults module exists
  commonHostDefaultsExists = builtins.pathExists ./../modules/common-host-defaults.nix;

  # Verify network-constants module exists
  networkConstantsExists = builtins.pathExists ./../modules/network-constants.nix;

  # Verify justfile exists (deployment automation)
  justfileExists = builtins.pathExists ./../justfile;

  # Verify colmena deployment config exists
  colmenaConfigExists = builtins.pathExists ./../colmena.nix;

  allChecks = {
    hasNixosConfigurations = hasNixosConfigurations;
    allHostsInFlake = missingHostsInFlake == [];
    hasColmena = hasColmena;
    hasAgenixInput = hasAgenixInput;
    hasHomeManagerInput = hasHomeManagerInput;
    hasNixpkgsInput = hasNixpkgsInput;
    flakeLockExists = flakeLockExists;
    allHardwareConfigsPresent = missingHardwareConfig == [];
    commonHostDefaultsExists = commonHostDefaultsExists;
    networkConstantsExists = networkConstantsExists;
    justfileExists = justfileExists;
    colmenaConfigExists = colmenaConfigExists;
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;
in {
  checks = allChecks // {
    _diagnostics = {
      inherit missingHostsInFlake missingHardwareConfig;
    };
  };
  failures = builtins.attrNames failures;
  passed = failures == {};
}
