# Podman Container Runtime Configuration
# Daemonless container engine, Docker-compatible CLI
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.podman;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;

in
{
  options.services.podman = {
    enable = mkEnableOption "Podman container runtime";

    # Enable Docker API compatibility (for tools that expect docker)
    dockerCompat = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Docker-compatible CLI (creates `docker` alias to `podman`)";
    };

    # Enable Podman Compose (docker-compose replacement)
    compose = mkOption {
      type = types.bool;
      default = true;
      description = "Install podman-compose for multi-container applications";
    };

    # Enable rootless container mode
    rootless = mkOption {
      type = types.bool;
      default = false;
      description = "Enable rootless containers (recommended for security)";
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # PODMAN DAEMON CONFIGURATION
    # ============================================================================
    virtualisation.podman = {
      enable = true;
      dockerCompat = cfg.dockerCompat;
      defaultNetwork.settings.dns_enabled = true;
    };

    # ============================================================================
    # ROOTLESS PODMAN (optional)
    # ============================================================================
    users.users.j_kro = mkIf cfg.rootless {
      extraGroups = [ "podman" ];
    };

    boot.kernelParams = mkIf cfg.rootless [ "user_namespace.enable=1" ];

    # ============================================================================
    # NETWORKING (optional)
    # ============================================================================
    networking.extraHosts = mkIf config.services.unbound-cluster.enable "127.0.0.1 $(hostname)";

    # ============================================================================
    # PODMAN COMPOSE & UTILITIES
    # ============================================================================
    environment.systemPackages =
      with pkgs;
      [
        podman-compose # docker-compose replacement
        podman-tui # Terminal UI for Podman
        skopeo # Container image operations
        buildah # Build container images
      ]
      ++ lib.optional cfg.rootless pasta;

    # ============================================================================
    # HELPER SCRIPTS
    # ============================================================================
    environment.etc."containers/registries.conf.d/00-github.conf".text = ''
      [registries.search]
      registries = ['docker.io', 'ghcr.io', 'quay.io']

      [registries.insecure]
      registries = []

      [registries.block]
      registries = []
    '';

    # Enable cgroup v2 for better resource control
    systemd.enableCgroupForMemory = true;
  };
}
