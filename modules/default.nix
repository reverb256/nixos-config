# NixOS Module Registry — auto-discovered via recursive tree walk.
#
# Instead of manually listing every module, this uses collect-modules.nix
# to recursively walk the modules/ directory tree and auto-import all .nix
# files that are NixOS modules.
#
# Libraries and non-module files are excluded via the skip/deny lists in
# lib/collect-modules.nix.
#
# To add a new module: create a .nix file anywhere under modules/.
# To add a new library: put it in a lib/ subdirectory or add to the
# excludeFiles list in lib/collect-modules.nix.
{lib, ...}: {
  imports = import ./lib/collect-modules.nix {
    inherit lib;
    basePath = ./.;
  };
}
