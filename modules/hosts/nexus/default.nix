# nexus host wiring - TWO-LAYER (host-wiring Q1 to B), Variant B (path-import).
#
# Mirror of modules/hosts/zephyr/default.nix (host #1 cutover, #398). Variant
# B: tests/k3s-topology-evidence.nix does builtins.readFile on
# ../hosts/nexus/configuration.nix by path, so the ORIGINAL classic file must
# survive byte-identical. Layer 1 therefore wraps it by PATH (zero body edits);
# Layer 2 composes the evaluator via the shared lib/dendritic-host.nix helper:
# commonModules ++ [ configuration.nix ] ++ extraModules.
#
# Layer 1: flake.modules.nixos.nexusConfig - the CONTENT (identity-first +
#           host body). Consumed by tests/colmena without a full nixosSystem.
# Layer 2: flake.nixosConfigurations.nexus - the EVALUATOR: composes
#           nexusConfig + base + feature imports via withSystem.
{
  inputs,
  config,
  self,
  withSystem,
  ...
}: {
  # A host file is itself a flake-parts module: host-private modules
  # (exactly-one-host features) are nested imports here so their
  # flake.modules.nixos.* keys self-register.
  # nexus's host-private features are already imported BY PATH inside
  # hosts/nexus/configuration.nix plus the classic modules/default.nix
  # registry, so no extra nested imports needed until the shared-file wraps
  # land (structure-first, shared-files-last).

  # Layer 1 - CONTENT. Variant B: wrap the real classic file by path so
  # source-grep tests keep passing byte-identical.
  flake.modules.nixos.nexusConfig = import ../../../hosts/nexus/configuration.nix;

  # Layer 2 - EVALUATOR. Shared helper composes the exact same module list
  # and specialArgs contract used by colmena.nix (single source of truth).
  flake.nixosConfigurations.nexus = withSystem "x86_64-linux" ({system, ...}: let
    commonModules = import ../../../common-modules-list.nix {inherit inputs self;};
    mkDendriticHost = import ../../../lib/dendritic-host.nix {
      inherit inputs self commonModules;
    };
  in
    (mkDendriticHost.mkHost {
      hostConfig = config.flake.modules.nixos.nexusConfig;
      extraModules = (import ../../../contracts/host-inventory.nix).hosts.nexus.extraModules;
      inherit system;
    }).system);
}
