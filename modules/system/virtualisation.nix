{pkgs, ...}: {
  virtualisation.podman = {
    enable = true;

    dockerCompat = true;

    defaultNetwork.settings.dns_enabled = true;
  };

  environment.variables.DBX_CONTAINER_MANAGER = "podman";

  environment.systemPackages = with pkgs; [
    nvidia-docker
    nerdctl

    distrobox

    qemu
    lima

    podman-compose
    podman-tui

    docker-compose

    lazydocker
  ];
}
