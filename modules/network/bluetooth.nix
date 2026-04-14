{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.networking.bluetooth;
  inherit
    (lib)
    mkEnableOption
    mkIf
    ;
in {
  options.networking.bluetooth = {
    enable = mkEnableOption "Bluetooth support via BlueZ";
  };

  config = mkIf cfg.enable {
    services.bluetooth = {
      enable = true;
      experimental = true;
    };

    users.groups.bluetooth = {};
    users.users.root.extraGroups = ["bluetooth"];

    environment.systemPackages = with pkgs; [
      bluez-tools
    ];
  };
}
