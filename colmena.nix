{
  inputs,
  self,
  hosts,
  commonModules,
}: let
  # Same evaluator helper as flake.nix and every dendritic host file: one
  # module-list + specialArgs contract for all deployment paths.
  mkDendriticHost = import ./lib/dendritic-host.nix {
    inherit inputs self commonModules;
  };
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
  # Deployment fields are required inventory values; missing fields fail
  # during evaluation rather than silently receiving a consumer default.
  mkColmenaHost = name: h:
    assert (h.hostName
      or (throw "mkColmenaHost: host '${name}' missing required hostName field — add to flake.nix's hosts attrset"))
    == name; {
      imports =
        (mkDendriticHost.mkHost {
          hostConfig = ./hosts/${name}/configuration.nix;
          extraModules = h.extraModules or [];
        }).modules;
      deployment = {
        targetHost = h.targetHost;
        buildOnTarget = h.buildOnTarget;
        tags = h.tags;
        targetUser = h.targetUser;
        # Deployment locality is inventory-owned rather than inferred from a
        # host-name conditional, so the same field is validated and consumed
        # everywhere.
        allowLocalDeployment = h.allowLocalDeployment;
      };
    };
in
  {
    meta = {
      nixpkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
      # nodeNixpkgs is derived from the unified `hosts` attrset — adding a new
      # host in flake.nix gives you a nodeNixpkgs entry here automatically.
      nodeNixpkgs = builtins.mapAttrs (_: _: tunedNixpkgs "x86_64-linux") hosts;
      machinesFile = ./machines;
      # Use the exact specialArgs factory used by the dendritic host evaluator.
      # Colmena's nodeNixpkgs remains overlay-tuned for deployment, while the
      # module argument contract is identical to nixosConfigurations.*.
      specialArgs = mkDendriticHost.mkSpecialArgs "x86_64-linux";
    };
  }
  // builtins.mapAttrs mkColmenaHost hosts
