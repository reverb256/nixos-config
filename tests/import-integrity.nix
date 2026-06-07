{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;

  defaultNix = builtins.readFile ../modules/default.nix;

  isImportLine = line: let
    trimmed = lib.strings.trim line;
  in
    lib.strings.hasPrefix "./" trimmed
    && lib.strings.hasSuffix ".nix" trimmed
    && !(lib.strings.hasPrefix "#" trimmed);

  importLines = map (line: lib.strings.trim line) (
    builtins.filter isImportLine (lib.splitString "\n" defaultNix)
  );

  resolvePath = path: let
    isDir = builtins.pathExists ../modules/${path} && lib.pathIsDirectory ../modules/${path};
  in
    if isDir
    then ../modules/${path}/default.nix
    else ../modules/${path};

  duplicates = lib.unique (
    builtins.filter (x: lib.lists.count (y: y == x) importLines > 1) importLines
  );

  validateImport = path: let
    resolved = resolvePath path;
    exists = builtins.pathExists resolved;
  in {
    inherit path;
    inherit exists;
  };

  results = map validateImport importLines;

  missingFiles = builtins.filter (r: !r.exists) results;

  summary = {
    totalImports = builtins.length importLines;
    inherit duplicates;
    missingFiles = map (r: r.path) missingFiles;
    passed = missingFiles == [] && duplicates == [];
  };
in
  assert summary.passed
  || (builtins.trace "" (
    builtins.trace "=== Import Integrity Test FAILED ===" (
      builtins.trace "Missing files: ${builtins.toJSON summary.missingFiles}" (
        builtins.trace "Duplicates: ${builtins.toJSON summary.duplicates}" (
          throw "Import integrity test failed"
        )
      )
    )
  )); summary
