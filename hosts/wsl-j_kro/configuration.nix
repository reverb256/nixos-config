# hosts/wsl-j_kro/configuration.nix
# NixOS-WSL dev box on THIS Windows PC (j_kro / krash Windows host).
# Composes the reusable WSL profile with the NixOS-WSL flake module.
#
# Management: registered as a node in modules/services/nixos-cluster-mcp.nix
# so the fleet's nixos-cluster-mcp server (running on nexus) can drive it
# (status / build / deploy / rollback). nexus reaches this box via the
# Windows-host netsh portproxy described in PR body + scripts/wsl-autostart.ps1.
{config, ...}: {
  imports = [
    ../../profiles/wsl.nix
  ];

  networking.hostName = "wsl-j_kro";

  # This Windows host (j_kro / krash) public key — allows passwordless ssh
  # from here. Base profile already carries j_kro@zephyr + krash@krash3.
  users.users.j_kro.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJo8yKBnF95ImOUhhUFDJyJ9IpCS9U4CqUiEiQ/RW7rH j_kro@krash3-windows"
  ];

  system.stateVersion = "26.11";
}
