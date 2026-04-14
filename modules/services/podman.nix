{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.podman;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in {
  options.services.podman = {
    enable = mkEnableOption "Podman container runtime";

    dockerCompat = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Docker-compatible CLI (creates `docker` alias to `podman`)";
    };

    compose = mkOption {
      type = types.bool;
      default = true;
      description = "Install podman-compose for multi-container applications";
    };

    rootless = mkOption {
      type = types.bool;
      default = false;
      description = "Enable rootless containers (recommended for security)";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.podman = {
      enable = true;
      inherit (cfg) dockerCompat;
      defaultNetwork.settings.dns_enabled = true;
    };

    users.users.j_kro = mkIf cfg.rootless {
      extraGroups = ["podman"];
    };

    boot.kernelParams = mkIf cfg.rootless ["user_namespace.enable=1"];

    networking.extraHosts = mkIf config.services.unbound-cluster.enable "127.0.0.1 $(hostname)";

    environment.systemPackages = with pkgs;
      [
        podman-compose
        podman-tui
        skopeo
        buildah
      ]
      ++ lib.optional cfg.rootless pasta;

    environment.etc."containers/policy.json".text = builtins.toJSON {
      default = [{ type = "reject"; }];
      transports = {
        "docker-daemon" = {
          "" = [{ type = "insecureAcceptAnything"; }];
        };
        "directory" = {
          "" = [{ type = "insecureAcceptAnything"; }];
        };
        "docker" = {
          "docker.io/library" = [{ type = "insecureAcceptAnything"; }];
          "docker.io" = [{ type = "insecureAcceptAnything"; }];
          "ghcr.io" = [{ type = "insecureAcceptAnything"; }];
          "quay.io" = [{ type = "insecureAcceptAnything"; }];
          "localhost" = [{ type = "insecureAcceptAnything"; }];
        };
        "atomic" = {
          "" = [{ type = "insecureAcceptAnything"; }];
        };
      };
    };

    environment.etc."containers/registries.conf.d/00-github.conf".text = ''
      [registries.search]
      registries = ['docker.io', 'ghcr.io', 'quay.io']

      [registries.insecure]
      registries = []

      [registries.block]
      registries = []
    '';

    systemd.enableCgroupForMemory = true;
  };
}
