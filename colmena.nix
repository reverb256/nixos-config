{
  inputs,
  self,
  hosts,
  commonModules,
}: let
  tunedNixpkgs = system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [((import ./overlays/default.nix) {inherit inputs;})];
    };

  # mkColmenaHost — derive per-host colmneda config from `hosts.<name>`.
  # Guard: assert that h.hostName, when present, matches the attrset key. If
  # h.hostName is missing (drift), throw loudly. The directory lookup uses
  # the attrset key (`name`) because that's what ./hosts/${name}/ names.
  # Defaults match legacy mkHost signature:
  #   targetHost    = null    (zephyr is the only local-deployable host)
  #   buildOnTarget = true    (per-cluster default; zephyr overrides to false)
  #   tags          = []      (colmneda tags are optional)
  mkColmenaHost = name: h:
    assert (h.hostName
      or (throw "mkColmenaHost: host '${name}' missing required hostName field — add to flake.nix's hosts attrset"))
      == name;
    {
      imports =
        commonModules
        ++ [./hosts/${name}/configuration.nix]
        ++ (h.extraModules or []);
      deployment = {
        targetHost = h.targetHost or null;
        buildOnTarget = h.buildOnTarget or true;
        tags = h.tags or [];
        targetUser = "j_kro";
        # Mirror the legacy `allowLocalDeployment` rule:
        # allow local build+activation only when targetHost is null (zephyr).
        allowLocalDeployment = h.targetHost == null;
      };
    };
in {
  meta = {
    nixpkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    # nodeNixpkgs is derived from the unified `hosts` attrset — adding a new
    # host in flake.nix gives you a nodeNixpkgs entry here automatically.
    nodeNixpkgs = builtins.mapAttrs (_: _: tunedNixpkgs "x86_64-linux") hosts;
    machinesFile = ./machines;
    specialArgs = {
      inherit inputs self;
      vfioPkgs = tunedNixpkgs "x86_64-linux"; # derived from inputs.nixpkgs via tunedNixpkgs
    };
  };
}
  // builtins.mapAttrs mkColmenaHost hosts
