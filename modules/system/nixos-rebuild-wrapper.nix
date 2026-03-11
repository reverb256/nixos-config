# NixOS Rebuild Wrapper Module
# Installs wrapper script that translates nixos-rebuild commands to Colmena
# for cluster-wide deployment consistency with GPU scheduler integration
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  # Install the wrapper script as nixos-rebuild
  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "nixos-rebuild" (builtins.readFile "${inputs.self}/scripts/nixos-rebuild-wrapper"))
  ];

  # Create /run/nixos-deploy directory for state tracking
  systemd.tmpfiles.rules = [
    "d /run/nixos-deploy 0755 root root -"
  ];
}
