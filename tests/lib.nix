# tests/lib.nix - Shared test infrastructure
#
# Provides helpers for writing NixOS module tests.
# Usage in test files:
#   { pkgs, ... }:
#   let
#     inherit (import ./lib.nix { inherit pkgs; }) evalModule assertModule;
#   in ...
#
{
  pkgs,
}:
let
  lib = pkgs.lib;

  # Evaluate a NixOS module in isolation (no full system config)
  evalModule =
    {
      modulePath ? null,
      module ? null,
      extraModules ? [ ],
    }:
    let
      mod = if modulePath != null then import modulePath else module;
      allModules = [ mod ] ++ extraModules;
    in
    lib.evalModules {
      modules = allModules;
      specialArgs = {
        inherit pkgs;
        config = { };
        lib = lib;
        options = { };
      };
    };

  # Assert that a module can be evaluated without errors
  assertModule =
    {
      name,
      modulePath,
    }:
    let
      result = builtins.tryEval (evalModule {
        inherit modulePath;
      });
    in
    {
      inherit name;
      success = result.success;
    };

  # Collect all .nix files from a directory (recursive)
  collectNixFiles =
    dir: builtins.filter (f: lib.strings.hasSuffix ".nix" f) (lib.filesystem.listFilesRecursive dir);

  # Filter out backup files
  isNotBackup =
    f:
    !(lib.strings.hasSuffix ".backup" f)
    && !(lib.strings.hasSuffix ".bak" f)
    && !(lib.strings.hasInfix ".backup." f);

in
{
  inherit
    evalModule
    assertModule
    collectNixFiles
    isNotBackup
    ;
}
