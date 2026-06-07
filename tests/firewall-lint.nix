{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;

  scanDirs = [
    ../modules/system
    ../modules/services
    ../modules/security
    ../modules/hardware
    ../modules/desktop
    ../modules/networking
    ../modules/network
    ../modules/mining
    ../modules/gaming
    ../modules/compute-market
    ../modules/common
  ];

  allNixFiles = lib.flatten (
    map (
      dir:
        if builtins.pathExists dir
        then builtins.filter (f: lib.strings.hasSuffix ".nix" f) (lib.filesystem.listFilesRecursive dir)
        else []
    )
    scanDirs
  );

  nixFiles =
    builtins.filter (
      f: !(lib.strings.hasSuffix ".backup" f) && !(lib.strings.hasInfix ".backup." f)
    )
    allNixFiles;

  unsafePatterns = [
    "allowedTCPPorts = ["
    "allowedUDPPorts = ["
    "allowedTCPPortRanges = ["
    "allowedUDPPortRanges = ["
  ];

  safePattern = "mkOptionDefault";

  checkFile = file: let
    content = builtins.readFile file;
    lines = lib.splitString "\n" content;

    findUnsafe = line: let
      hasUnsafe = builtins.any (p: lib.strings.hasInfix p line) unsafePatterns;
      hasSafe = lib.strings.hasInfix safePattern line;
      isComment = lib.strings.hasPrefix "#" (lib.strings.trim line);
    in
      hasUnsafe && !hasSafe && !isComment;

    unsafeLines = builtins.filter findUnsafe lines;
    hasViolation = builtins.length unsafeLines > 0;

    relPath = lib.strings.removePrefix (toString ../.. + "/") file;
  in {
    file = relPath;
    inherit unsafeLines;
    inherit hasViolation;
  };

  results = map checkFile nixFiles;

  violations = builtins.filter (r: r.hasViolation) results;
in {
  filesScanned = builtins.length nixFiles;
  violations =
    map (r: {
      inherit (r) file;
      lines = r.unsafeLines;
    })
    violations;
  passed = violations == [];
}
