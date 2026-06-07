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

  checkModule = path: let
    resolved = resolvePath path;
    content =
      if builtins.pathExists resolved
      then builtins.readFile resolved
      else "";
    hasContent = content != "";

    hasEnableOption =
      hasContent
      && (lib.strings.hasInfix "mkEnableOption" content || lib.strings.hasInfix "mkOption" content);

    hasMkIf = hasContent && lib.strings.hasInfix "mkIf" content;

    hasUnsafePortAssignment = let
      hasDirectPortAssign =
        lib.strings.hasInfix "allowedTCPPorts = [" content
        || lib.strings.hasInfix "allowedUDPPorts = [" content;
      hasMkOptionDefault = lib.strings.hasInfix "mkOptionDefault" content;
    in
      hasDirectPortAssign && !hasMkOptionDefault;

    isExempt =
      lib.strings.hasInfix "network-constants" path
      || lib.strings.hasInfix "common-host-defaults" path
      || lib.strings.hasInfix "firewall-ports" path
      || lib.strings.hasInfix "environment-variables" path
      || lib.strings.hasInfix "overlay" path
      || lib.strings.hasSuffix "/default.nix" path;
  in {
    inherit path;
    exists = builtins.pathExists resolved;
    hasEnableOption = hasEnableOption || isExempt;
    hasMkIf = hasMkIf || isExempt;
    inherit hasUnsafePortAssignment;
    inherit isExempt;
    compliant = (hasEnableOption || isExempt) && !hasUnsafePortAssignment;
  };

  results = map checkModule importLines;

  nonCompliant = builtins.filter (r: !r.compliant) results;
  unsafePorts = builtins.filter (r: r.hasUnsafePortAssignment) results;
in {
  total = builtins.length results;
  compliant = builtins.length results - builtins.length nonCompliant;
  nonCompliant =
    map (r: {
      inherit (r) path;
      reason =
        if !r.hasEnableOption
        then "missing-enable-option"
        else if r.hasUnsafePortAssignment
        then "unsafe-port-assignment"
        else "other";
    })
    nonCompliant;
  unsafePortModules = map (r: r.path) unsafePorts;
  passed = nonCompliant == [];
}
