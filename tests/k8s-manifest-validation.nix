{pkgs ? import <nixpkgs> {}}: let
  lib = pkgs.lib;
  testLib = import ./lib.nix { inherit pkgs; };

  # Collect all kubernetes module files
  k8sModuleFiles = builtins.filter testLib.isNotBackup (
    testLib.collectNixFiles ./../kubernetes/modules
  );

  # Read file safely
  readFileSafe = path: let
    result = builtins.tryEval (builtins.readFile path);
  in if result.success then result.value else "";

  # Check: k8s modules should set a namespace (not default)
  missingNamespace = let
    check = path: let
      src = readFileSafe path;
      hasNamespace = lib.strings.hasInfix "namespace" src;
      hasEasykubenix = lib.strings.hasInfix "easykubenix" src || lib.strings.hasInfix "kubenix" src;
    in if hasEasykubenix && !hasNamespace then [{ path = toString path; }] else [];
  in lib.flatten (builtins.map check k8sModuleFiles);

  # Check: k8s modules should not hardcode image tags (use variables/let bindings)
  hardcodedImageTags = let
    check = path: let
      src = readFileSafe path;
      lines = lib.splitString "\n" src;
      isHardcodedImage = line:
        lib.strings.hasInfix "image = " line &&
        lib.strings.hasInfix ":" line &&
        # Allow variable references
        !(lib.strings.hasInfix "let " (readFileSafe path) && lib.strings.hasInfix "image" line && lib.strings.hasInfix "\${" line) &&
        # Skip comments
        !(lib.hasPrefix "#" (lib.strings.trim line));
      # Simple heuristic: image = "registry/image:tag" with a specific tag
      # is fine if the tag is a let-bound variable, but suspicious if literal
      isLiteralTag = line: let
        trimmed = lib.strings.trim line;
      in
        isHardcodedImage line &&
        # Pattern: image = "something:latest" or image = "something:v1.2.3"
        builtins.match ".*image += +\"[^\"]+:[a-zA-Z0-9._-]+\".*" trimmed != null &&
        # Exclude if tag is a nix variable reference
        !(lib.strings.hasInfix "\${" line);
      offending = builtins.filter isLiteralTag lines;
    in if offending != [] then [{ path = toString path; lines = offending; }] else [];
  in lib.flatten (builtins.map check k8sModuleFiles);

  # Check: k8s modules that define services should include labels
  missingLabels = let
    check = path: let
      src = readFileSafe path;
      hasService = lib.strings.hasInfix "Service" src || lib.strings.hasInfix "service" src;
      hasLabels = lib.strings.hasInfix "labels" src;
    in if hasService && !hasLabels then [{ path = toString path; }] else [];
  in lib.flatten (builtins.map check k8sModuleFiles);

  # Check: k8s modules should not use hostPort (security risk)
  usesHostPort = let
    check = path: let
      src = readFileSafe path;
    in if lib.strings.hasInfix "hostPort" src then [{ path = toString path; }] else [];
  in lib.flatten (builtins.map check k8sModuleFiles);

  # Check: k8s modules with persistent data should reference PVC or volume
  missingVolumes = let
    check = path: let
      src = readFileSafe path;
      hasStatefulSet = lib.strings.hasInfix "StatefulSet" src;
      hasDeployment = lib.strings.hasInfix "Deployment" src;
      hasPVC = lib.strings.hasInfix "PersistentVolumeClaim" src || lib.strings.hasInfix "pvc" src;
      hasVolume = lib.strings.hasInfix "volumeClaim" src || lib.strings.hasInfix "volumes" src;
      isStateful = hasStatefulSet || (hasDeployment && (lib.strings.hasInfix "postgres" src || lib.strings.hasInfix "database" src || lib.strings.hasInfix "data" src));
    in if isStateful && !(hasPVC || hasVolume) then [{ path = toString path; }] else [];
  in lib.flatten (builtins.map check k8sModuleFiles);

  allChecks = {
    allK8sModulesHaveNamespace = missingNamespace == [];
    noHardcodedImageTags = hardcodedImageTags == [];
    allServicesHaveLabels = missingLabels == [];
    noHostPortUsage = usesHostPort == [];
    statefulWorkloadsHaveVolumes = missingVolumes == [];
    k8sModulesDirectoryExists = builtins.pathExists ./../kubernetes/modules;
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;
in {
  checks = allChecks // {
    _diagnostics = {
      inherit missingNamespace hardcodedImageTags missingLabels;
      inherit usesHostPort missingVolumes;
      totalK8sModules = builtins.length k8sModuleFiles;
    };
  };
  failures = builtins.attrNames failures;
  passed = failures == {};
}
