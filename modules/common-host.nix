{...}: {
  imports = [
    ./common-host-defaults.nix

    ./system/ssh.nix

    ./desktop/desktop.nix

    ./system/tailscale.nix

    ./services/garnix.nix

    ./services/auto-update.nix

    ./system/distributed-builds.nix

    ./services/whisper-dictation.nix

    ./network-constants.nix

    ./system/mosh.nix
  ];
}
