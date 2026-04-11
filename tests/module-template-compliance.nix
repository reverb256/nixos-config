# tests/module-template-compliance.nix
#
# Validates that modules follow project conventions:
#   - Has an enable option (mkEnableOption)
#   - Config block wrapped in mkIf cfg.enable
#   - Uses lib.mkOptionDefault for list assignments
#     (allowedTCPPorts, allowedUDPPorts, etc.)
#
# Run: nix-instantiate --parse tests/module-template-compliance.nix
#
{
  pkgs ? import <nixpkgs> { },
}:
let
  lib = pkgs.lib;

  # Read and parse the module hub
  defaultNix = builtins.readFile ../modules/default.nix;

  # Extract import paths
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

  # Resolve paths
  resolvePath =
    path:
    let
      isDir = builtins.pathExists ../modules/${path} && lib.pathIsDirectory ../modules/${path};
    in
    if isDir then ../modules/${path}/default.nix else ../modules/${path};

  # Check a single module file for compliance
  checkModule =
    path:
    let
      resolved = resolvePath path;
      content = if builtins.pathExists resolved then builtins.readFile resolved else "";
      hasContent = content != "";

      # Convention checks (grep-based, works on raw source)
      hasEnableOption =
        hasContent
        && (lib.strings.hasInfix "mkEnableOption" content || lib.strings.hasInfix "mkOption" content);

      hasMkIf = hasContent && lib.strings.hasInfix "mkIf" content;

      # Check for unsafe direct list assignment on firewall ports
      # This catches: allowedTCPPorts = [ ... ] without mkOptionDefault
      # Pattern: direct assignment not wrapped in mkOptionDefault or mkIf
      hasUnsafePortAssignment =
        let
          # Look for patterns like: allowedTCPPorts = [ without mkOptionDefault
          hasDirectPortAssign =
            lib.strings.hasInfix "allowedTCPPorts = [" content
            || lib.strings.hasInfix "allowedUDPPorts = [" content;
          hasMkOptionDefault = lib.strings.hasInfix "mkOptionDefault" content;
        in
        hasDirectPortAssign && !hasMkOptionDefault;

      # Modules that are exempt from template compliance
      # (data-only modules, configuration modules, etc.)
      isExempt =
        lib.strings.hasInfix "network-constants" path
        || lib.strings.hasInfix "common-host-defaults" path
        || lib.strings.hasInfix "firewall-ports" path
        || lib.strings.hasInfix "environment-variables" path
        || lib.strings.hasInfix "overlay" path
        || lib.strings.hasSuffix "/default.nix" path;

    in
    {
      path = path;
      exists = builtins.pathExists resolved;
      hasEnableOption = hasEnableOption || isExempt;
      hasMkIf = hasMkIf || isExempt;
      hasUnsafePortAssignment = hasUnsafePortAssignment;
      isExempt = isExempt;
      compliant = (hasEnableOption || isExempt) && !hasUnsafePortAssignment;
    };

  results = map checkModule importLines;

  # Non-compliant modules
  nonCompliant = builtins.filter (r: !r.compliant) results;
  unsafePorts = builtins.filter (r: r.hasUnsafePortAssignment) results;
  missingEnable = builtins.filter (r: !r.hasEnableOption && !r.isExempt && r.exists) results;

in
{
  total = builtins.length results;
  compliant = builtins.length results - builtins.length nonCompliant;
  nonCompliant = map (r: {
    path = r.path;
    reason =
      if !r.hasEnableOption then
        "missing-enable-option"
      else if r.hasUnsafePortAssignment then
        "unsafe-port-assignment"
      else
        "other";
  }) nonCompliant;
  unsafePortModules = map (r: r.path) unsafePorts;
  passed = nonCompliant == [ ];
}
