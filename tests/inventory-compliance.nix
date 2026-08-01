{ pkgs, ... }:
let
  inherit (pkgs) lib;
  inventory = import ../contracts/host-inventory.nix;
  contract = import ../contracts/layer-interface.nix;
  schema = import ../contracts/host-inventory-schema.nix { inherit lib; };
  hostNames = builtins.attrNames inventory.hosts;
  metadataDir = ../hosts/metadata;
  metadataNames = builtins.filter
    (name: lib.hasSuffix ".json" name)
    (builtins.attrNames (builtins.readDir metadataDir));
  metadataHosts = map (name: lib.removeSuffix ".json" name) metadataNames;
  metadataPath = host: metadataDir + "/${host}.json";
  metadataFor = host:
    if builtins.pathExists (metadataPath host)
    then builtins.fromJSON (builtins.readFile (metadataPath host))
    else { };
  metadata = lib.genAttrs hostNames metadataFor;
  metadataHost = host: metadata.${host};
  inventoryHost = host: inventory.hosts.${host};

  typedInventory =
    lib.evalModules {
      modules = [
        schema
        { config.hosts = inventory.hosts; }
      ];
    };

  requiredMetadataFields = [
    "hostName"
    "targetHost"
    "targetUser"
    "tags"
    "buildOnTarget"
    "allowLocalDeployment"
    "ipAddress"
    "interfaceName"
  ];

  metadataHasRequiredFields = host:
    builtins.all (field: builtins.hasAttr field (metadataHost host)) requiredMetadataFields;

  metadataMatches = host: let
    expected = inventoryHost host;
    actual = metadataHost host;
  in
    metadataHasRequiredFields host
    && actual.hostName == expected.hostName
    && actual.targetHost == expected.targetHost
    && actual.targetUser == expected.targetUser
    && actual.tags == expected.tags
    && actual.buildOnTarget == expected.buildOnTarget
    && actual.allowLocalDeployment == expected.allowLocalDeployment
    && actual.ipAddress == expected.ipAddress
    && actual.interfaceName == expected.interfaceName;

  hostDirectoryExists = host: builtins.pathExists ../hosts/${host};
  hostConfigurationExists = host: builtins.pathExists ../hosts/${host}/configuration.nix;
  hostHardwareExists = host: builtins.pathExists ../hosts/${host}/hardware-configuration.nix;
  extraModulesExist = host:
    builtins.all builtins.pathExists (inventoryHost host).extraModules;

  checks = {
    schemaVersionSupported = inventory.schemaVersion == 1;
    interfaceVersionSupported = inventory.interfaceVersion == "1.0";
    typedInventoryEvaluates = typedInventory.config.hosts == inventory.hosts;
    canonicalHostSet = hostNames == [ "forge" "nexus" "sentry" "zephyr" ];
    metadataSetMatchesInventory =
      lib.sort builtins.lessThan metadataHosts
      == lib.sort builtins.lessThan hostNames;
    metadataFieldsPresent = builtins.all metadataHasRequiredFields hostNames;
    metadataMatchesInventory = builtins.all metadataMatches hostNames;
    hostDirectoriesPresent = builtins.all hostDirectoryExists hostNames;
    hostConfigurationsPresent = builtins.all hostConfigurationExists hostNames;
    hostHardwarePresent = builtins.all hostHardwareExists hostNames;
    extraModulesPresent = builtins.all extraModulesExist hostNames;
    layerContractBindsInventory =
      contract.interfaces.infrastructureToPlatform.version == "1.0"
      && contract.interfaces.infrastructureToPlatform.producer == "infrastructure"
      && contract.interfaces.infrastructureToPlatform.consumer == "platform"
      && contract.interfaces.infrastructureToPlatform.sourceOfTruth
      == "contracts/host-inventory.nix:hosts"
      && builtins.elem "host-capabilities" contract.interfaces.infrastructureToPlatform.fields
      && builtins.elem "deployment-targets" contract.interfaces.infrastructureToPlatform.fields
      && builtins.elem "builder-capabilities" contract.interfaces.infrastructureToPlatform.fields;
  };

  failures = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
  diagnostics = {
    hostNames = hostNames;
    metadataHosts = metadataHosts;
    missingMetadata = lib.subtractLists metadataHosts hostNames;
    orphanedMetadata = lib.subtractLists hostNames metadataHosts;
    metadataMismatches = builtins.filter (host: !metadataMatches host) hostNames;
    missingExtraModules = builtins.concatLists (builtins.map
      (host: builtins.filter (path: !builtins.pathExists path) (inventoryHost host).extraModules)
      hostNames);
  };
in
{
  inherit checks failures diagnostics;
  passed = failures == [ ];
}
