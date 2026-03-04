# NixOS Bluetooth Module
# Enables Bluetooth support via bluez

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.networking.bluetooth;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;

in
{
  options.networking.bluetooth = {
    enable = mkEnableOption "Bluetooth support via BlueZ";
  };

  config = mkIf cfg.enable {
    # Enable BlueZ Bluetooth stack
    services.bluetooth = {
      enable = true;
      # Enable experimental features for newer Bluetooth devices
      experimental = true;
    };

    # Add user to bluetooth group for access
    users.groups.bluetooth = { };
    users.users.root.extraGroups = [ "bluetooth" ];

    # Add bluez-tools for command-line Bluetooth management
    environment.systemPackages = with pkgs; [
      bluez-tools
    ];
  };
}
