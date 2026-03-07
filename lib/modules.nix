# lib/modules.nix --- Module discovery and loading utilities
#
# Heavily inspired by hlissner/dotfiles
# Provides mapModules, mapModulesRec, mapHosts for auto-discovery

{ lib, attrs }:

let
  inherit (builtins)
    attrValues
    readDir
    pathExists
    concatLists
    attrNames
    isAttrs
    mapAttrs
    mapAttrsToList;

  inherit (lib)
    id
    mapAttrs'
    filterAttrs
    hasPrefix
    hasSuffix
    nameValuePair
    removeSuffix
    ;

  # Helper to check if path is a directory with default.nix
  hasDefaultNix = path:
    pathExists "${path}/default.nix";

  # Helper to check if file is a Nix file (but not flake.nix or default.nix)
  isNixFile = name: v:
    v == "regular" &&
    name != "default.nix" &&
    name != "flake.nix" &&
    hasSuffix ".nix" name;
in
rec {
  # Map modules in a directory to attrset
  # Directories become named after their dirname, files lose .nix suffix
  # Skips hidden (starts with _) entries
  #
  # mapModules ./modules → { desktop = import ./modules/desktop; ... }
  mapModules = dir: fn:
    mapAttrs'
      (n: v:
        let path = "${toString dir}/${n}"; in
        if v == "directory" && hasDefaultNix path
        then nameValuePair n (fn path)
        else if isNixFile n v
        then nameValuePair (removeSuffix ".nix" n) (fn path)
        else nameValuePair "" null)
      (n: v: v != null && !(hasPrefix "_" n))
      (readDir dir);

  # Map modules to a list of values
  mapModules' = dir: fn:
    attrValues (mapModules dir fn);

  # Recursively map modules, preserving directory structure
  # mapModulesRec ./modules → { desktop = { apps = { ... }; }; ... }
  mapModulesRec = dir: fn:
    mapAttrs'
      (n: v:
        let path = "${toString dir}/${n}"; in
        if v == "directory"
        then nameValuePair n (mapModulesRec path fn)
        else if isNixFile n v
        then nameValuePair (removeSuffix ".nix" n) (fn path)
        else nameValuePair "" null)
      (n: v: v != null && !(hasPrefix "_" n))
      (readDir dir);

  # Recursively map modules to flat list
  mapModulesRec' = dir: fn:
    let
      dirs =
        mapAttrsToList
          (k: _: "${dir}/${k}")
          (filterAttrs
            (n: v: v == "directory"
                   && !(hasPrefix "_" n)
                   && !(pathExists "${dir}/${n}/.noload"))
            (readDir dir));
      files = attrValues (mapModules dir id);
      paths = files ++ concatLists (map (d: mapModulesRec' d id) dirs);
    in map fn paths;

  # Map host configurations from a directory
  # Each host directory should contain a configuration.nix
  mapHosts = dir:
    mapModules dir (path: {
      inherit path;
      config = import path;
    });
}
