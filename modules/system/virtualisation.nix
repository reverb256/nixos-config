# Virtualisation Module
# Podman, containers, and virtualisation tools from XNM1
{
  pkgs,
  lib,
  ...
}: {
  # ============================================================================
  # PODMAN (Docker alternative)
  # ============================================================================
  virtualisation.podman = {
    enable = true;

    # Create a `docker` alias for podman (drop-in replacement)
    dockerCompat = true;
    dockerSocket.enable = lib.mkForce true; # Override common-base.nix setting

    # Required for containers under podman-compose to talk to each other
    defaultNetwork.settings.dns_enabled = true;
  };

  # Environment variables for distrobox
  environment.variables.DBX_CONTAINER_MANAGER = "podman";

  # Add user to podman group (done in host config)
  # users.users.j_kro.extraGroups = [ "podman" ];

  # ============================================================================
  # PACKAGES
  # ============================================================================
  environment.systemPackages = with pkgs; [
    # Container tools
    nvidia-docker # NVIDIA container runtime
    nerdctl # Docker-compatible CLI for containerd

    # Distrobox - Distro containers on top of Podman
    distrobox

    # Virtual machines
    qemu # QEMU machine emulator
    lima # Linux virtual machines on macOS (and Linux)

    # Podman ecosystem
    podman-compose # Docker-compose replacement for Podman
    podman-tui # Terminal UI for Podman

    # Docker compose (still useful with podman compat)
    docker-compose

    # Container management
    lazydocker # Terminal UI for Docker/Podman
  ];
}
