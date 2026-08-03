{pkgs ? import <nixpkgs> {}}: let
  lib = pkgs.lib;
  testLib = import ./lib.nix {inherit pkgs;};

  moduleFiles = builtins.filter testLib.isNotBackup (
    testLib.collectNixFiles ./../modules
  );

  readFileSafe = path: let
    result = builtins.tryEval (builtins.readFile path);
  in
    if result.success
    then result.value
    else "";

  # An enable option only needs an accompanying mkIf in the SAME file when
  # that file also applies config. Pure option aggregators (profiles/*,
  # network-options, gaming.nix) declare options and delegate the mkIf-gated
  # config to imported implementation files — that is a legitimate pattern.
  hasEnableWithoutMkIf = path: let
    src = readFileSafe path;
    declaresOption = lib.strings.hasInfix "mkEnableOption" src;
    appliesConfig = lib.strings.hasInfix "config = " src;
  in
    declaresOption && appliesConfig && !(lib.strings.hasInfix "mkIf" src);

  hasUnsafeMode = path: let
    src = readFileSafe path;
  in
    lib.strings.hasInfix "mode = \"777\"" src || lib.strings.hasInfix "mode = \"666\"" src;

  # Firewall port assignments must use mkOptionDefault. Comments are ignored
  # (e.g. alert-webhook.nix documents a local-only service with a commented
  # allowedTCPPorts line).
  hasUnsafeFirewallAssignment = path: let
    src = readFileSafe path;
    lines = lib.splitString "\n" src;
    isAssignment = line: let
      trimmed = lib.strings.trim line;
    in
      !(lib.hasPrefix "#" trimmed)
      && (lib.strings.hasInfix "allowedTCPPorts = [" trimmed
        || lib.strings.hasInfix "allowedUDPPorts = [" trimmed);
    hasActiveAllowed = builtins.any isAssignment lines;
    hasMkOptionDefault = lib.strings.hasInfix "mkOptionDefault" src;
  in
    hasActiveAllowed && !hasMkOptionDefault;

  moduleResults =
    builtins.map (path: {
      path = toString path;
      enableWithoutMkIf = hasEnableWithoutMkIf path;
      hasUnsafeMode = hasUnsafeMode path;
      hasUnsafeFirewall = hasUnsafeFirewallAssignment path;
    })
    moduleFiles;

  modulesWithEnableNoMkIf = builtins.filter (r: r.enableWithoutMkIf) moduleResults;
  modulesWithUnsafeMode = builtins.filter (r: r.hasUnsafeMode) moduleResults;
  modulesWithUnsafeFirewall = builtins.filter (r: r.hasUnsafeFirewall) moduleResults;

  allChecks = {
    enableOptionsUseMkIf = modulesWithEnableNoMkIf == [];
    noUnsafeFileModes = modulesWithUnsafeMode == [];
    firewallUsesMkOptionDefault = modulesWithUnsafeFirewall == [];
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;
in {
  checks =
    allChecks
    // {
      _diagnostics = {
        inherit modulesWithEnableNoMkIf modulesWithUnsafeMode modulesWithUnsafeFirewall;
        totalModulesChecked = builtins.length moduleFiles;
      };
    };
  failures = builtins.attrNames failures;
  passed = failures == {};
}
