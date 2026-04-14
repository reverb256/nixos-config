{lib}:
with builtins;
with lib; let
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
