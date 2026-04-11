# tests/firewall-lint.nix
#
# Lints all NixOS module files for unsafe firewall port list assignments.
# Direct assignment (allowedTCPPorts = [ ... ]) silently replaces host-level
# config instead of merging with it. Must use lib.mkOptionDefault.
#
# This is a critical safety rule: direct assignment can break SSH access.
#
# Run: nix-instantiate --parse tests/firewall-lint.nix
#
{
  pkgs ? import <nixpkgs> { },
}:
let
  lib = pkgs.lib;

  # Directories to scan
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

  # Collect all .nix files from scan directories
  allNixFiles = lib.flatten (
    map (
      dir:
      if builtins.pathExists dir then
        builtins.filter (f: lib.strings.hasSuffix ".nix" f) (lib.filesystem.listFilesRecursive dir)
      else
        [ ]
    ) scanDirs
  );

  # Filter out backup files
  nixFiles = builtins.filter (
    f: !(lib.strings.hasSuffix ".backup" f) && !(lib.strings.hasInfix ".backup." f)
  ) allNixFiles;

  # Unsafe patterns that indicate direct list assignment
  # These patterns assign lists directly without mkOptionDefault
  unsafePatterns = [
    "allowedTCPPorts = ["
    "allowedUDPPorts = ["
    "allowedTCPPortRanges = ["
    "allowedUDPPortRanges = ["
  ];

  # Safe patterns that indicate proper merging
  safePattern = "mkOptionDefault";

  # Check a single file for unsafe firewall assignments
  checkFile =
    file:
    let
      content = builtins.readFile file;
      lines = lib.splitString "\n" content;

      # Find lines with unsafe patterns
      findUnsafe =
        line:
        let
          hasUnsafe = builtins.any (p: lib.strings.hasInfix p line) unsafePatterns;
          # Skip if the line contains mkOptionDefault (safe assignment)
          hasSafe = lib.strings.hasInfix safePattern line;
          # Skip comments
          isComment = lib.strings.hasPrefix "#" (lib.strings.trim line);
        in
        hasUnsafe && !hasSafe && !isComment;

      unsafeLines = builtins.filter findUnsafe lines;
      hasViolation = builtins.length unsafeLines > 0;

      # Get relative path for cleaner output
      relPath = lib.strings.removePrefix (toString ../.. + "/") file;

    in
    {
      file = relPath;
      unsafeLines = unsafeLines;
      hasViolation = hasViolation;
    };

  results = map checkFile nixFiles;

  # Only report files with violations
  violations = builtins.filter (r: r.hasViolation) results;

in
{
  filesScanned = builtins.length nixFiles;
  violations = map (r: {
    file = r.file;
    lines = r.unsafeLines;
  }) violations;
  passed = violations == [ ];
}
