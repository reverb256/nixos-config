{pkgs}: let
  inherit (pkgs) lib;

  evalModule = {
    modulePath ? null,
    module ? null,
    extraModules ? [],
  }: let
    mod =
      if modulePath != null
      then import modulePath
      else module;
    allModules = [mod] ++ extraModules;
  in
    lib.evalModules {
      modules = allModules;
      specialArgs = {
        inherit pkgs;
        config = {};
        inherit lib;
        options = {};
      };
    };

  assertModule = {
    name,
    modulePath,
  }: let
    result = builtins.tryEval (evalModule {
      inherit modulePath;
    });
  in {
    inherit name;
    inherit (result) success;
  };

  collectNixFiles = dir: builtins.filter (f: lib.strings.hasSuffix ".nix" f) (lib.filesystem.listFilesRecursive dir);

  isNotBackup = f:
    !(lib.strings.hasSuffix ".backup" f)
    && !(lib.strings.hasSuffix ".bak" f)
    && !(lib.strings.hasInfix ".backup." f);
in {
  inherit
    evalModule
    assertModule
    collectNixFiles
    isNotBackup
    ;
}
