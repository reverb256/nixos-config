# lib/attrs.nix --- Attribute set utilities
#
# Heavily inspired by hlissner/dotfiles
# Provides helpers for working with nested attribute sets
{lib}:
with builtins; with lib; let
  # Flatten an attrset, concatenating names with '.'
  # flattenAttrs { a.b = 1; c = 2; } => { "a.b" = 1; c = 2; }
  flattenAttrs = prefix: attrs:
    foldl' (
      acc: name: let
        v = getAttr name attrs;
        newName =
          if prefix == ""
          then name
          else "${prefix}.${name}";
      in
        if isAttrs v && !isDerivation v
        then acc // flattenAttrs newName v
        else acc // {${newName} = v;}
    ) {} (attrNames attrs);
in {
  inherit flattenAttrs;
}
