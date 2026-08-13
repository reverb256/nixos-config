# Shared Phase 1 host evaluator.
#
# This is deliberately content-source agnostic: Phase 1 still accepts the
# classic hosts/<host>/configuration.nix module, while every evaluator consumes
# the same module list and specialArgs. Phase 2 can replace hostConfig with a
# native flake.modules.nixos.* body without changing consumers.
{
  inputs,
  self,
  commonModules,
}: let
  mkPkgs = system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  mkSpecialArgs = system: {
    inherit inputs;
    vfioPkgs = mkPkgs system;
  };
in {
  inherit mkPkgs mkSpecialArgs;

  mkHost = {
    hostConfig,
    extraModules ? [],
    system ? "x86_64-linux",
  }: let
    modules = commonModules ++ [hostConfig] ++ extraModules;
    specialArgs = mkSpecialArgs system;
  in {
    inherit modules specialArgs;
    system = inputs.nixpkgs.lib.nixosSystem {
      inherit system modules specialArgs;
    };
  };
}
