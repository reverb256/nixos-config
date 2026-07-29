{
  inputs,
  self,
}: let
  metadata = import ./metadata.nix;
  traits = import ./traits.nix { inherit inputs self; };
  inherit (metadata) zephyr nexus forge sentry;
in {
  inherit metadata;

  mkHost = { hostName, extraModules ? [ ] }:
    nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs vfioPkgs self metadata traits;
      };
      modules =
        commonModules
        ++ [ ./hosts/${hostName}/configuration.nix ]
        ++ extraModules;
    };

  nixosConfigurations = builtins.mapAttrs (_name: value: mkHost { hostName = value.hostName; }) metadata;

  colmena = import ./colmena.nix {
    inherit inputs self;
    inherit metadata traits;
  };
}
