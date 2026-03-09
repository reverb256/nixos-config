# lib/default.nix --- Custom library entry point
#
# Combines attrs and modules libraries, extends nixpkgs lib
{lib, ...}: let
  inherit
    (builtins)
    mapAttrs
    attrValues
    ;

  inherit
    (lib)
    mapAttrs'
    nameValuePair
    ;

  # Import sub-libraries
  attrs = import ./attrs.nix {inherit lib;};
  modules = import ./modules.nix {inherit lib attrs;};
in {
  inherit attrs modules;

  # Re-export nixpkgs lib for convenience
  inherit
    (lib)
    attrNames
    attrValues
    mapAttrs
    mapAttrs'
    filterAttrs
    hasPrefix
    hasSuffix
    removeSuffix
    nameValuePair
    optional
    optionalString
    mkIf
    mkEnableOption
    mkOption
    mkDefault
    mkForce
    mkOrder
    types
    literalExpression
    genAttrs
    listToAttrs
    foldl'
    concatMap
    concatLists
    imap
    imap0
    zipAttrsWith
    zipAttrsWithNames
    ;
}
