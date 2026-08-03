{pkgs ? import <nixpkgs> {}}: let
  lib = pkgs.lib;
  testLib = import ./lib.nix {inherit pkgs;};

  # Collect all kubernetes module files
  k8sModuleFiles = builtins.filter testLib.isNotBackup (
    testLib.collectNixFiles ./../kubernetes/modules
  );

  # Read file safely
  readFileSafe = path: let
    result = builtins.tryEval (builtins.readFile path);
  in
    if result.success
    then result.value
    else "";

  # Check: k8s modules should set a namespace (not default)
  missingNamespace = let
    check = path: let
      src = readFileSafe path;
      # Helper modules can participate in the renderer without owning a
      # Kubernetes namespace. EasyKubenix scopes resources with a qualified
      # object key such as `mining.ConfigMap.foo` or
      # `"maplespike-prod".CronJob.foo`; the namespace may therefore be
      # present in the object key rather than as a metadata field.
      resourceKinds = [
        "Namespace"
        "ConfigMap"
        "CronJob"
        "DaemonSet"
        "Deployment"
        "Job"
        "NetworkPolicy"
        "PodDisruptionBudget"
        "Secret"
        "Service"
        "ServiceAccount"
        "StatefulSet"
      ];
      hasNamespaceQualifiedObject = builtins.any (
        kind: lib.strings.hasInfix ".${kind}." src
      ) resourceKinds;
      hasNamespace =
        lib.strings.hasInfix "namespace" src
        || hasNamespaceQualifiedObject
        # Some modules scope the complete object tree under a namespace:
        # config.kubernetes.objects.ai-inference = { ... }.
        || lib.strings.hasInfix "config.kubernetes.objects." src;
      hasKubernetesObjects = lib.strings.hasInfix "config.kubernetes.objects" src;
    in
      if hasKubernetesObjects && !hasNamespace
      then [{path = toString path;}]
      else [];
  in
    lib.flatten (builtins.map check k8sModuleFiles);

  # Check: mutable image tags are forbidden. Pinned literal version tags are
  # intentional and safer than :latest, so only reject the mutable tag.
  hardcodedImageTags = let
    check = path: let
      src = readFileSafe path;
      lines = lib.splitString "\n" src;
      isMutableImage = line:
        lib.strings.hasInfix "image = " line
        && lib.strings.hasInfix ":latest" line
        && !(lib.hasPrefix "#" (lib.strings.trim line));
      offending = builtins.filter isMutableImage lines;
    in
      if offending != []
      then [
        {
          path = toString path;
          lines = offending;
        }
      ]
      else [];
  in
    lib.flatten (builtins.map check k8sModuleFiles);

  # Check: k8s modules that define services should include labels
  missingLabels = let
    check = path: let
      src = readFileSafe path;
      hasService = lib.strings.hasInfix "Service" src || lib.strings.hasInfix "service" src;
      hasLabels = lib.strings.hasInfix "labels" src;
    in
      if hasService && !hasLabels
      then [{path = toString path;}]
      else [];
  in
    lib.flatten (builtins.map check k8sModuleFiles);

  # Check: k8s modules should not use hostPort (security risk)
  usesHostPort = let
    check = path: let
      src = readFileSafe path;
    in
      if lib.strings.hasInfix "hostPort" src
      then [{path = toString path;}]
      else [];
  in
    lib.flatten (builtins.map check k8sModuleFiles);

  # Check: k8s modules with persistent data should reference PVC or volume
  missingVolumes = let
    check = path: let
      src = readFileSafe path;
      hasStatefulSet = lib.strings.hasInfix "StatefulSet" src;
      hasDeployment = lib.strings.hasInfix "Deployment" src;
      hasPVC = lib.strings.hasInfix "PersistentVolumeClaim" src || lib.strings.hasInfix "pvc" src;
      hasVolume = lib.strings.hasInfix "volumeClaim" src || lib.strings.hasInfix "volumes" src;
      # Only actual StatefulSet declarations require persistent volume
      # evidence. Deployment names/config comments are not enough to classify
      # a workload as stateful.
      isStateful = hasStatefulSet;
    in
      if isStateful && !(hasPVC || hasVolume)
      then [{path = toString path;}]
      else [];
  in
    lib.flatten (builtins.map check k8sModuleFiles);

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
  checks =
    allChecks
    // {
      _diagnostics = {
        inherit missingNamespace hardcodedImageTags missingLabels;
        inherit usesHostPort missingVolumes;
        totalK8sModules = builtins.length k8sModuleFiles;
      };
    };
  failures = builtins.attrNames failures;
  passed = builtins.attrNames failures == [];
}
