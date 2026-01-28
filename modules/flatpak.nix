{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    services.flatpak = {
      enable = mkEnableOption "Flatpak sandbox application support";
      enableExtraAppstream = mkEnableOption "Include extra AppStream metadata";
      enableExtraAppstreamRemote = mkEnableOption "Enable extra AppStream remote repositories";
    };
  };

  config = mkIf config.services.flatpak.enable {
    # Enable Flatpak support
    services.flatpak.enable = true;
    services.flatpak.enableExtraAppstream = true;
    services.flatpak.enableExtraAppstreamRemote = true;

    # Ensure flatpak-system-helper service is available
    systemd.services.flatpak-system-helper = {
      description = "Flatpak system helper";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-logind.service" ];
      wants = [ "systemd-logind.service" ];
    };

    # Enable Flathub repository for app installation
    environment.systemPackages = with pkgs; [ flatpak ];
    
    # Configure AppStream for proper metadata handling
    environment.variables.APPSTREAM_ALLOW_FAKING_SYSTEM_REMOTE = "1";
  };
}