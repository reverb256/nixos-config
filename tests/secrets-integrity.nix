{pkgs ? import <nixpkgs> {}}: let
  lib = pkgs.lib;

  registrySource = builtins.readFile ./../modules/system/agenix-secrets-registry.nix;

  # Extract .age filenames from file = "..." paths in the registry
  extractAgeFilenames = src: let
    lines = lib.splitString "\n" src;
    isFileLine = line: lib.strings.hasInfix "secrets/" line && lib.strings.hasInfix ".age" line;
    fileLines = builtins.filter isFileLine lines;
    extractFilename = line: let
      parts = lib.splitString "/secrets/" line;
      afterSecrets = if builtins.length parts > 1 then
        let tail = builtins.elemAt parts (builtins.length parts - 1);
            ageParts = lib.splitString ".age" tail;
        in if builtins.length ageParts > 0 then
          builtins.elemAt ageParts 0 + ".age"
        else null
      else null;
    in afterSecrets;
    filenames = builtins.filter (f: f != null) (builtins.map extractFilename fileLines);
  in lib.unique filenames;

  # Get all .age files actually present in secrets/
  secretsDir = ./../secrets;
  ageFilesOnDisk = let
    allFiles = builtins.readDir secretsDir;
    ageOnly = lib.filterAttrs (name: type:
      type == "regular" && lib.strings.hasSuffix ".age" name
    ) allFiles;
  in builtins.attrNames ageOnly;

  # Extract referenced filenames from the registry
  referencedAgeFiles = extractAgeFilenames registrySource;

  # Check: all referenced .age files exist on disk
  missingOnDisk = builtins.filter (f:
    !(builtins.elem f ageFilesOnDisk)
  ) referencedAgeFiles;

  # Check: all .age files on disk are referenced somewhere (catches orphans)
  orphanedOnDisk = builtins.filter (f:
    !(builtins.elem f referencedAgeFiles)
  ) ageFilesOnDisk;

  # Check: no secret has mode "777" or "666" (overly permissive)
  unsafeModes = let
    lines = lib.splitString "\n" registrySource;
    isUnsafeMode = line:
      (lib.strings.hasInfix "mode = " line) &&
      (lib.strings.hasInfix "777" line || lib.strings.hasInfix "666" line);
  in builtins.filter isUnsafeMode lines;

  # Check: initrd secrets use host-specific filenames (prevent sharing)
  initrdSecretsProperlyScoped = let
    lines = lib.splitString "\n" registrySource;
    initrdLines = builtins.filter (l: lib.strings.hasInfix "initrd-ssh-host-key" l) lines;
    hasHostNameRef = lib.any (l:
      lib.strings.hasInfix "config.networking.hostName" l
    ) initrdLines;
  in if initrdLines == [] then true else hasHostNameRef;

  # Check: secrets.nix (agenix) file exists if referenced
  secretsNixExists = builtins.pathExists ./../secrets/secrets.nix;

  allChecks = {
    allReferencedSecretsExist = missingOnDisk == [];
    noOrphanedSecretFiles = orphanedOnDisk == [];
    noUnsafeModes = unsafeModes == [];
    initrdSecretsHostScoped = initrdSecretsProperlyScoped;
    secretsDirectoryExists = builtins.pathExists secretsDir;
    registryFileExists = builtins.pathExists ./../modules/system/agenix-secrets-registry.nix;
    secretsNixExists = secretsNixExists;
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;
in {
  checks = allChecks // {
    _diagnostics = {
      inherit missingOnDisk orphanedOnDisk unsafeModes;
      totalAgeFilesOnDisk = builtins.length ageFilesOnDisk;
      totalReferencedSecrets = builtins.length referencedAgeFiles;
    };
  };
  failures = builtins.attrNames failures;
  passed = failures == {};
}
