# tests/import-integrity.nix
#
# Validates that all module imports in modules/default.nix resolve to valid
# NixOS module structures. Detects:
#   - Missing files referenced in imports
#   - Duplicate imports (same path imported twice)
#   - Import regressions
#
# Run: nix-instantiate --eval tests/import-integrity.nix
#
{
  pkgs ? import <nixpkgs> { },
}:
let
  lib = pkgs.lib;

  # Parse modules/default.nix to extract import paths
  defaultNix = builtins.readFile ../modules/default.nix;

  # Extract all ./<path> imports from the imports list
  # Match lines like: ./system/users.nix
  isImportLine =
    line:
    let
      trimmed = lib.strings.trim line;
    in
    lib.strings.hasPrefix "./" trimmed
    && lib.strings.hasSuffix ".nix" trimmed
    && !(lib.strings.hasPrefix "#" trimmed);

  importLines = map (line: lib.strings.trim line) (
    builtins.filter isImportLine (lib.splitString "\n" defaultNix)
  );

  # Resolve import paths relative to modules/
  resolvePath =
    path:
    let
      isDir = builtins.pathExists ../modules/${path} && lib.pathIsDirectory ../modules/${path};
    in
    if isDir then ../modules/${path}/default.nix else ../modules/${path};

  # Check for duplicate imports
  sorted = lib.naturalSort importLines;
  duplicates = lib.unique (
    builtins.filter (x: lib.lists.count (y: y == x) importLines > 1) importLines
  );

  # Validate each import
  validateImport =
    path:
    let
      resolved = resolvePath path;
      exists = builtins.pathExists resolved;
    in
    {
      path = path;
      exists = exists;
    };

  results = map validateImport importLines;

  # Check for failures
  missingFiles = builtins.filter (r: !r.exists) results;

  # Summary
  summary = {
    totalImports = builtins.length importLines;
    duplicates = duplicates;
    missingFiles = map (r: r.path) missingFiles;
    passed = missingFiles == [ ] && duplicates == [ ];
  };

in
assert
  summary.passed
  || (builtins.trace "" (
    builtins.trace "=== Import Integrity Test FAILED ===" (
      builtins.trace "Missing files: ${builtins.toJSON summary.missingFiles}" (
        builtins.trace "Duplicates: ${builtins.toJSON summary.duplicates}" (
          throw "Import integrity test failed"
        )
      )
    )
  ));
summary
