# Docker Module for OpenClaw Sandboxing
{ config, lib, pkgs, ... }:

with lib;

{
  options.virtualisation.docker = {
    enable = mkEnableOption "Docker container runtime";
  };

  config = mkIf config.virtualisation.docker.enable {
    virtualisation.docker.enable = true;
    virtualisation.docker.enableOnBoot = true;
    
    # Add user to docker group
    users.users.j_kro.extraGroups = [ "docker" ];
    
    # Install docker-compose
    environment.systemPackages = with pkgs; [
      docker-compose
    ];
  };
}
