{pkgs ? import <nixpkgs> {}}: let
  lib = pkgs.lib;
  testLib = import ./lib.nix { inherit pkgs; };

  moduleFiles = builtins.filter testLib.isNotBackup (
    testLib.collectNixFiles ./../modules
  );

  readFileSafe = path: let
    result = builtins.tryEval (builtins.readFile path);
  in if result.success then result.value else "";

  hasEnableWithoutMkIf = path: let
    src = readFileSafe path;
  in lib.strings.hasInfix "mkEnableOption" src && !(lib.strings.hasInfix "mkIf" src);

  hasUnsafeMode = path: let
    src = readFileSafe path;
  in lib.strings.hasInfix "mode = \"777\"" src || lib.strings.hasInfix "mode = \"666\"" src;

  hasUnsafeFirewallAssignment = path: let
    src = readFileSafe path;
    hasAllowed = lib.strings.hasInfix "allowedTCPPorts = [" src || lib.strings.hasInfix "allowedUDPPorts = [" src;
    hasMkOptionDefault = lib.strings.hasInfix "mkOptionDefault" src;
  in hasAllowed && !hasMkOptionDefault;

  moduleResults = builtins.map (path: {
    path = toString path;
    enableWithoutMkIf = hasEnableWithoutMkIf path;
    hasUnsafeMode = hasUnsafeMode path;
    hasUnsafeFirewall = hasUnsafeFirewallAssignment path;
  }) moduleFiles;

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
  checks = allChecks // {
    _diagnostics = {
      inherit modulesWithEnableNoMkIf modulesWithUnsafeMode modulesWithUnsafeFirewall;
      totalModulesChecked = builtins.length moduleFiles;
    };
  };
  failures = builtins.attrNames failures;
  passed = failures == {};
}
