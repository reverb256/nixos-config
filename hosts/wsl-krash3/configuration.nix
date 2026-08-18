# hosts/wsl-krash3/configuration.nix
# NixOS-WSL dev box on THIS Windows PC (krash3 / j_kro).
# Composes the reusable WSL profile with the NixOS-WSL flake module.
# Adds: RTX 4060 GPU passthrough + CUDA ComfyUI (art-asset pipeline for Anime Arena).
{config, inputs, pkgs, lib, ...}: {
  imports = [
    ../../profiles/wsl.nix
    inputs.comfyui-nix.nixosModules.default
  ];

  networking.hostName = "nixos-wsl-krash3";

  # RTX 4060 is exposed to the WSL guest automatically via /dev/dxg
  # (NixOS-WSL mounts the Windows GPU; no explicit wsl.gpu option in this version).

  # This Windows host (krash3) public key - allows passwordless ssh from here.
  users.users.j_kro.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJo8yKBnF95ImOUhhUFDJyJ9IpCS9U4CqUiEiQ/RW7rH j_kro@krash3-windows"
  ];

  # CUDA ComfyUI systemd service (RTX 4060, 8GB -> lowvram for safety).
  # The comfyui-nix module auto-adds its own nixpkgs overlay.
  services.comfyui = {
    enable = true;
    gpuSupport = "cuda";
    # Manager (comfyui-manager) fails comfyui-nix's strict runtime-deps check
    # upstream; we add custom nodes declaratively instead, so disable it.
    enableManager = false;
    port = 8188;
    listenAddress = "127.0.0.1";
    dataDir = "/home/j_kro/comfyui-data";
    user = "j_kro";
    group = "users";
    createUser = false;
    openFirewall = false;
    extraArgs = [ "--lowvram" ];
  };

  system.stateVersion = "26.11";
}
