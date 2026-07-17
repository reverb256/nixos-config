# hosts/wsl-krash3/configuration.nix
# NixOS-WSL dev box on THIS Windows PC (krash3 / j_kro).
# Composes the reusable WSL profile with the NixOS-WSL flake module.
{config, ...}: {
  imports = [
    ../../profiles/wsl.nix
  ];

  networking.hostName = "nixos-wsl-krash3";

  # This Windows host (krash3) public key — allows passwordless ssh from here.
  users.users.j_kro.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJo8yKBnF95ImOUhhUFDJyJ9IpCS9U4CqUiEiQ/RW7rH j_kro@krash3-windows"
  ];

  system.stateVersion = "26.11";
}
