# Upstream nix-csi module with builtins.currentSystem fix
# The upstream module uses builtins.currentSystem which breaks in certain
# evaluation contexts. We override _module.args to use pkgs.system instead.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Disable the problematic _module.args.curPkgs from upstream
  _module.args.curPkgs = pkgs;

  imports = [
    "${inputs.nix-csi}/kubenix"
  ];
}
