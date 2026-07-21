# Mining services module — minimal stub for peakminer GPU mining
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.mining;
in
{
  options.services.mining = {
    enable = mkEnableOption "Mining services (peakminer GPU mining)";
    user = mkOption {
      type = types.str;
      default = "mining";
      description = "User to run mining services as";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = "mining";
      extraGroups = ["video" "render"];
    };
    users.groups.mining = { };

    boot.kernel.sysctl."vm.nr_hugepages" = 1280;

    systemd.tmpfiles.rules = [
      "d /var/lib/mining 0750 ${cfg.user} mining -"
      "d /var/log/mining 0750 ${cfg.user} mining -"
    ];
  };
}
