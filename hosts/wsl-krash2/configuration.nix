# hosts/wsl-krash2/configuration.nix
# NixOS-WSL dev box on krash2 (10.1.1.79, Windows PC, krash admin).
# Composes the reusable WSL profile with the NixOS-WSL flake module.
{config, ...}: {
  imports = [
    ../../profiles/wsl.nix
  ];

  networking.hostName = "nixos-wsl-krash2";

  # krash2's Windows-side key (if any) goes here. Base profile already
  # carries j_kro@zephyr + krash@krash3; add the krash2 key below once
  # generated so passwordless ssh from krash2 works.
  #
  # users.users.j_kro.openssh.authorizedKeys.keys = [
  #   "ssh-ed25519 AAAA... j_kro@krash2-windows"
  # ];

  system.stateVersion = "26.11";
}
