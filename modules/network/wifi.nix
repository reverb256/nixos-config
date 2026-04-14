{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.networking.wifi;
  inherit
    (lib)
    mkEnableOption
    mkIf
    ;
in {
  options.networking.wifi = {
    enable = mkEnableOption "WiFi support via NetworkManager and wpa_supplicant";
  };

  config = mkIf cfg.enable {
    networking.networkmanager = {
      enable = true;
      wifi.backend = "native";
    };

    users.groups.wireshark = {};
    users.users.root.extraGroups = ["wireshark"];

    environment.systemPackages = with pkgs; [
      wifi-cli
    ];
  };
}
