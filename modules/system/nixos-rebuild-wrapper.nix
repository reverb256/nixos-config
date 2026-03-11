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
  # Install both the wrapper and native nixos-rebuild
  # - Wrapper takes precedence in PATH (named "nixos-rebuild")
  # - Native binary available as "nixos-rebuild-ng" in PATH
  # - Native binary accessible at /run/current-system/sw/bin/nixos-rebuild
  #
  # NATIVE BINARY AVAILABILITY:
  # NixOS automatically provides /run/current-system/sw/bin/nixos-rebuild as a
  # symlink to the nixos-rebuild-ng package when it's included in systemPackages.
  # The wrapper script uses this full path for bypass scenarios to avoid recursion.
  #
  # We also create an explicit symlink (.nixos-rebuild-native) for clarity.
  environment.systemPackages = with pkgs; [
    # Wrapper script (overrides nixos-rebuild command in PATH)
    (pkgs.writeShellScriptBin "nixos-rebuild" (builtins.readFile "${inputs.self}/scripts/nixos-rebuild-wrapper"))
    # Native nixos-rebuild (ensures /run/current-system/sw/bin/nixos-rebuild exists)
    pkgs.nixos-rebuild-ng
  ];

  # Create /run/nixos-deploy directory for state tracking
  # Also create explicit symlink to native binary for wrapper bypass scenarios
  systemd.tmpfiles.rules = [
    "d /run/nixos-deploy 0755 root root -"
    "L+ /run/current-system/sw/bin/.nixos-rebuild-native - - - - ${pkgs.nixos-rebuild-ng}/bin/nixos-rebuild"
  ];
}
