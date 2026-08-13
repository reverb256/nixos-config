{pkgs ? import <nixpkgs> {}}: let
  lib = pkgs.lib;
  hosts = ["zephyr" "nexus" "forge" "sentry"];
  inventory = import ../contracts/host-inventory.nix;
  # Source checks remain intentionally lightweight; full host evaluation is
  # performed by the flake's host drvPath checks in CI/build jobs.
  flakeSource = builtins.readFile ../flake.nix;
  colmenaSource = builtins.readFile ../colmena.nix;
  helperPath = ../lib/dendritic-host.nix;
  helperSource = builtins.readFile helperPath;

  wrapperPath = host: ../modules/hosts/${host}/default.nix;
  wrapperSource = host: builtins.readFile (wrapperPath host);

  wrapperChecks = lib.genAttrs hosts (host: let
    wrapper = wrapperSource host;
  in
    builtins.pathExists (wrapperPath host)
    && lib.strings.hasInfix "flake.modules.nixos.${host}Config" wrapper
    && lib.strings.hasInfix "flake.nixosConfigurations.${host}" wrapper
    && lib.strings.hasInfix "lib/dendritic-host.nix" wrapper
    && lib.strings.hasInfix "hostConfig = config.flake.modules.nixos.${host}Config" wrapper
    && lib.strings.hasInfix "hosts.${host}.extraModules" wrapper
    && builtins.pathExists ../hosts/${host}/configuration.nix);

  inventoryChecks = lib.genAttrs hosts (host:
    builtins.hasAttr host inventory.hosts
    && inventory.hosts.${host}.hostName == host
    && builtins.pathExists (wrapperPath host)
    && builtins.pathExists ../hosts/${host}/configuration.nix);

  checks = {
    all_expected_hosts_have_wrappers = builtins.all (v: v) (builtins.attrValues wrapperChecks);
    all_expected_hosts_are_in_inventory = builtins.all (v: v) (builtins.attrValues inventoryChecks);
    shared_helper_exists =
      builtins.pathExists helperPath
      && lib.strings.hasInfix "inputs.nixpkgs.lib.nixosSystem" helperSource
      && lib.strings.hasInfix "commonModules ++ [hostConfig] ++ extraModules" helperSource
      && lib.strings.hasInfix "mkSpecialArgs = system" helperSource;
    shared_helper_has_explicit_module_and_argument_contract =
      lib.strings.hasInfix "inherit modules specialArgs" helperSource
      && lib.strings.hasInfix "vfioPkgs = mkPkgs system" helperSource;
    colmena_uses_shared_helper =
      lib.strings.hasInfix "mkDendriticHost = import ./lib/dendritic-host.nix" colmenaSource
      && lib.strings.hasInfix ".modules" colmenaSource
      && lib.strings.hasInfix "mkDendriticHost.mkSpecialArgs" colmenaSource;
    classic_shim_dissolved =
      !(lib.strings.hasInfix "mkClassicNixosSystem" flakeSource)
      && !(lib.strings.hasInfix "classicNixosConfigurations" flakeSource)
      && !(lib.strings.hasInfix "classicHosts" flakeSource);
  };

  failures = builtins.attrNames (lib.filterAttrs (_: value: !value) checks);
in {
  inherit checks failures wrapperChecks inventoryChecks;
  passed = failures == [];
}
