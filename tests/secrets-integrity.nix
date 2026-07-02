{pkgs ? import <nixpkgs> {}}: let
  lib = pkgs.lib;

  registrySource = builtins.readFile ./../modules/system/sops-secrets-registry.nix;

  # Extract sopsFile paths from the registry
  extractSopsFileNames = src: let
    lines = lib.splitString "\n" src;
    isSopsFileLine = line:
      lib.strings.hasInfix "sopsFile" line
      && lib.strings.hasInfix "secrets/" line
      && (lib.strings.hasInfix ".yaml" line || lib.strings.hasInfix ".yml" line);
    fileLines = builtins.filter isSopsFileLine lines;
    extractFilename = line: let
      parts = lib.splitString "secrets/" line;
      afterSecrets = if builtins.length parts > 1 then
        let tail = builtins.elemAt parts (builtins.length parts - 1);
            # Split on quote chars to isolate the path
            quoteParts = lib.splitString "\"" tail;
        in if builtins.length quoteParts > 0 then
          builtins.elemAt quoteParts 0
        else null
      else null;
    in afterSecrets;
    filenames = builtins.filter (f: f != null) (builtins.map extractFilename fileLines);
  in lib.unique filenames;

  # Collect all .yaml files actually present in secrets/ subdirectories
  sopsFileNamesFromFragments = let
    subdirs = ["ai" "k8s" "cloud" "infra" "monitoring" "mining" "storage" "automation" "selfhosting" "ci" "default"];
    paths = builtins.map (d: builtins.toString ./../secrets + "/" + d) subdirs;
    allFiles = builtins.concatLists (builtins.map (p:
      if builtins.pathExists p then
        builtins.filter (f: builtins.strings?hasSuffix f ".yaml") (builtins.attrNames (builtins.readDir p))
      else []
    ) paths);
  in allFiles;

  # Referenced secret files from registry
  referencedYamlFiles = extractSopsFileNames registrySource;

  # Check: every referenced yaml file exists on disk
  missingYamlFiles = builtins.filter (f:
    !(builtins.elem f sopsFileNamesFromFragments)
  ) referencedYamlFiles;

  # Check no secret has mode "777" or "666"
  unsafeModes = let
    lines = lib.splitString "\n" registrySource;
    isUnsafeMode = line:
      (lib.strings.hasInfix "mode = " line)
      && (lib.strings.hasInfix "777" line || lib.strings.hasInfix "666" line);
  in builtins.filter isUnsafeMode lines;

  allChecks = {
    allReferencedSecretsExist = missingYamlFiles == [];
    noUnsafeModes = unsafeModes == [];
    secretsDirectoryExists = builtins.pathExists ./../secrets;
    registryFileExists = builtins.pathExists ./../modules/system/sops-secrets-registry.nix;
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;
in {
  checks = allChecks // {
    _diagnostics = {
      inherit unsafeModes missingYamlFiles;
      totalReferencedSecrets = builtins.length referencedYamlFiles;
      totalYamlFilesOnDisk = builtins.length sopsFileNamesFromFragments;
    };
  };
  failures = builtins.attrNames failures;
  passed = failures == [];
}
