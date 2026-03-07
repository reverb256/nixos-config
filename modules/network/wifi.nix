# NixOS WiFi Module
# Enables WiFi support via NetworkManager and wpa_supplicant
{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.networking.wifi;
  inherit
    (lib)
    mkEnableOption
    mkIf
    ;
in
{
  options.networking.wifi = {
    enable = mkEnableOption "WiFi support via NetworkManager and wpa_supplicant";
  };

  config = mkIf cfg.enable {
    # WiFi support via NetworkManager
    networking.networkmanager = {
      enable = true;
      wifi.backend = "native";
    };

    # Allow users to manage WiFi via NetworkManager
    users.groups.wireshark = { };
    users.users.root.extraGroups = [ "wireshark" ];

    # Add wifi-cli package for command-line WiFi management
    environment.systemPackages = with pkgs; [
      wifi-cli
    ];
  };
}
