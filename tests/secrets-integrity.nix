{pkgs ? import <nixpkgs> {}}: let
  lib = pkgs.lib;

  # Post-secretspec-migration (2026-07-25) the live source of truth for
  # which sops file backs which secret is secretspec.toml's [providers]
  # section (sops_* = "sops:///etc/nixos/secrets/<path>.yaml"). The old
  # sops-nix registry (modules/system/sops-secrets-registry.nix) now only
  # declares options, so scanning it would pass vacuously.
  secretspecSource = builtins.readFile ./../secretspec.toml;
  registrySource = builtins.readFile ./../modules/system/sops-secrets-registry.nix;

  # Extract secrets/ paths from secretspec.toml sops:// provider aliases
  extractSopsFileNames = src: let
    lines = lib.splitString "\n" src;
    isSopsUri = line:
      lib.strings.hasInfix "sops:///etc/nixos/secrets/" line;
    uriLines = builtins.filter isSopsUri lines;
    extractFilename = line: let
      parts = lib.splitString "/etc/nixos/secrets/" line;
      afterSecrets =
        if builtins.length parts > 1
        then let
          tail = builtins.elemAt parts (builtins.length parts - 1);
          # Trim trailing quote / newline
          quoteParts = lib.splitString "\"" tail;
        in
          if builtins.length quoteParts > 0
          then builtins.elemAt quoteParts 0
          else null
        else null;
    in
      afterSecrets;
    filenames = builtins.filter (f: f != null) (builtins.map extractFilename uriLines);
  in
    lib.unique filenames;

  # Collect all .yaml files actually present in secrets/ subdirectories
  sopsFileNamesFromFragments = let
    subdirs = ["ai" "k8s" "cloud" "infra" "monitoring" "mining" "storage" "automation" "selfhosting" "ci" "default"];
  in
    builtins.concatLists (builtins.map (
        d: let
          dirPath = builtins.toString ./../secrets + "/" + d;
        in
          if builtins.pathExists dirPath
          then
            builtins.map (f: d + "/" + f) (
              builtins.filter (f: lib.strings.hasSuffix ".yaml" f) (builtins.attrNames (builtins.readDir dirPath))
            )
          else []
      )
      subdirs);

  # Referenced secret files from secretspec.toml
  referencedYamlFiles = extractSopsFileNames secretspecSource;

  # Check: every referenced yaml file exists on disk
  missingYamlFiles =
    builtins.filter (
      f:
        !(builtins.elem f sopsFileNamesFromFragments)
    )
    referencedYamlFiles;

  # Check no secret has mode "777" or "666"
  unsafeModes = let
    lines = lib.splitString "\n" registrySource;
    isUnsafeMode = line:
      (lib.strings.hasInfix "mode = " line)
      && (lib.strings.hasInfix "777" line || lib.strings.hasInfix "666" line);
  in
    builtins.filter isUnsafeMode lines;

  allChecks = {
    allReferencedSecretsExist = missingYamlFiles == [];
    noUnsafeModes = unsafeModes == [];
    secretsDirectoryExists = builtins.pathExists ./../secrets;
    registryFileExists = builtins.pathExists ./../secretspec.toml;
  };

  failedChecks = lib.filterAttrs (_: v: v == false) allChecks;
  failureNames = builtins.attrNames failedChecks;
in {
  checks =
    allChecks
    // {
      _diagnostics = {
        inherit unsafeModes missingYamlFiles;
        totalReferencedSecrets = builtins.length referencedYamlFiles;
        totalYamlFilesOnDisk = builtins.length sopsFileNamesFromFragments;
      };
    };
  failures = failureNames;
  passed = failureNames == [];
}
