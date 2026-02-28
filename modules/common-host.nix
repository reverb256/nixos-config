# Common Host Module - Shared imports for cluster nodes that use desktop/gaming
{...}: {
  imports = [
    ./common-host-defaults.nix
    ./desktop/desktop.nix
    ./development/fish-starship.nix
    ./system/tailscale.nix
    ./services/garnix.nix
    ./services/auto-update.nix
    ./system/distributed-builds.nix
    ./mining/mining-build-wrapper.nix
  ];
}
