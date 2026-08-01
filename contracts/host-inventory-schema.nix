{ lib }:
{
  options.hosts = lib.mkOption {
    description = "Canonical Infrastructure layer host inventory.";
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        hostName = lib.mkOption { type = lib.types.str; };
        targetHost = lib.mkOption { type = lib.types.nullOr lib.types.str; };
        targetUser = lib.mkOption { type = lib.types.str; };
        buildOnTarget = lib.mkOption { type = lib.types.bool; };
        allowLocalDeployment = lib.mkOption { type = lib.types.bool; };
        tags = lib.mkOption { type = lib.types.listOf lib.types.str; };
        system = lib.mkOption { type = lib.types.str; };
        memoryMiB = lib.mkOption { type = lib.types.ints.positive; };
        capabilities = lib.mkOption { type = lib.types.listOf lib.types.str; };
        ipAddress = lib.mkOption { type = lib.types.str; };
        interfaceName = lib.mkOption { type = lib.types.str; };
        extraModules = lib.mkOption { type = lib.types.listOf lib.types.path; };
      };
    });
  };
}
