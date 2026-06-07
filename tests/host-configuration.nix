{pkgs ? import <nixpkgs> {}}: let
  lib = pkgs.lib;

  expectedHosts = {
    zephyr.ip = "10.1.1.110";
    nexus.ip = "10.1.1.120";
    forge.ip = "10.1.1.130";
    sentry.ip = "10.1.1.140";
  };

  requiredFiles = [ "configuration.nix" "hardware.nix" "firewall.nix" "services.nix" ];

  hostDirExists = host: builtins.pathExists ./../hosts/${host};
  hostFileExists = host: file: builtins.pathExists ./../hosts/${host}/${file};

  hasClusterNetworking = host:
    lib.strings.hasInfix "clusterNetworking" (builtins.readFile ./../hosts/${host}/configuration.nix);

  importsDefaultModule = host:
    lib.strings.hasInfix "modules/default.nix" (builtins.readFile ./../hosts/${host}/configuration.nix);

  firewallNonEmpty = host:
    builtins.stringLength (builtins.readFile ./../hosts/${host}/firewall.nix) > 10;

  correctIPRef = host: ip: let
    src = builtins.readFile ./../hosts/${host}/configuration.nix;
  in lib.strings.hasInfix "hosts.${host}.ip" src || lib.strings.hasInfix "\"${ip}\"" src;

  allHosts = builtins.attrNames expectedHosts;
  existingHosts = builtins.filter hostDirExists allHosts;

  missingFilesPerHost = builtins.mapAttrs (host: cfg:
    builtins.filter (f: !(hostFileExists host f)) requiredFiles
  ) (lib.genAttrs existingHosts (_: {}));

  # Cross-contamination: host references another host's path
  hostCrossContamination = let
    check = host: let
      src = builtins.readFile ./../hosts/${host}/configuration.nix;
      others = builtins.filter (h: h != host) allHosts;
      contaminated = builtins.filter (o: lib.strings.hasInfix "hosts/${o}/" src) others;
    in if contaminated != [] then { ${host} = contaminated; } else {};
  in lib.foldl' (acc: h: acc // (check h)) {} existingHosts;

  allChecks = {
    allHostDirsPresent = builtins.length (builtins.filter (h: !(hostDirExists h)) allHosts) == 0;

    allRequiredFilesPresent = lib.all (host:
      builtins.filter (f: !(hostFileExists host f)) requiredFiles == []
    ) existingHosts;

    allHaveClusterNetworking =
      builtins.filter (h: !(hasClusterNetworking h)) existingHosts == [];

    allImportDefaultModule =
      builtins.filter (h: !(importsDefaultModule h)) existingHosts == [];

    allFirewallsNonEmpty =
      builtins.filter (h: !(firewallNonEmpty h)) existingHosts == [];

    allHaveCorrectIPRef = lib.all (host:
      correctIPRef host expectedHosts.${host}.ip
    ) existingHosts;

    noCrossContamination = hostCrossContamination == {};
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;
in {
  checks = allChecks // {
    _diagnostics = {
      missingHostDirs = builtins.filter (h: !(hostDirExists h)) allHosts;
      inherit hostCrossContamination;
    };
  };
  failures = builtins.attrNames failures;
  passed = failures == {};
}
