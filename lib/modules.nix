{lib}: let
  inherit
    (builtins)
    attrValues
    readDir
    pathExists
    concatLists
    mapAttrsToList
    ;
  inherit
    (lib)
    id
    mapAttrs'
    filterAttrs
    hasPrefix
    hasSuffix
    nameValuePair
    removeSuffix
    ;
  hasDefaultNix = path:
    pathExists "${path}/default.nix";
  isNixFile = name: v:
    v
    == "regular"
    && name != "default.nix"
    && name != "flake.nix"
    && hasSuffix ".nix" name;
in rec {
  mapModules = dir: fn:
    mapAttrs'
    (n: v: let
      path = "${toString dir}/${n}";
    in
      if v == "directory" && hasDefaultNix path
      then nameValuePair n (fn path)
      else if isNixFile n v
      then nameValuePair (removeSuffix ".nix" n) (fn path)
      else nameValuePair "" null)
    (n: v: v != null && !(hasPrefix "_" n))
    (readDir dir);
  mapModules' = dir: fn:
    attrValues (mapModules dir fn);
  mapModulesRec = dir: fn:
    mapAttrs'
    (n: v: let
      path = "${toString dir}/${n}";
    in
      if v == "directory"
      then nameValuePair n (mapModulesRec path fn)
      else if isNixFile n v
      then nameValuePair (removeSuffix ".nix" n) (fn path)
      else nameValuePair "" null)
    (n: v: v != null && !(hasPrefix "_" n))
    (readDir dir);
  mapModulesRec' = dir: fn: let
    dirs =
      mapAttrsToList
      (k: _: "${dir}/${k}")
      (filterAttrs
        (n: v:
          v
          == "directory"
          && !(hasPrefix "_" n)
          && !(pathExists "${dir}/${n}/.noload"))
        (readDir dir));
    files = attrValues (mapModules dir id);
    paths = files ++ concatLists (map (d: mapModulesRec' d id) dirs);
  in
    map fn paths;
  mapHosts = dir:
    mapModules dir (path: {
      inherit path;
      config = import path;
    });
}
