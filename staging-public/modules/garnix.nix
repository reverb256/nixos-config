{config, lib, ...}:
let
  cfg = config.services.garnix;
in
{
  options.services.garnix = {
    enable = lib.mkEnableOption "Garnix CI/CD cache configuration";
    netrcFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/agenix/garnix-netrc";
      description = "Path to garnix netrc file with cache credentials";
    };
  };

  config = lib.mkIf cfg.enable {
    # Nix settings for Garnix
    nix.settings = {
      # Reduce TTL for presigned URLs that expire
      narinfo-cache-positive-ttl = 3600;
    };

    # Create netrc file with Garnix credentials
    environment.etc."nix/netrc".source = cfg.netrcFile;
    environment.etc."nix/netrc".mode = "0600";

    # Ensure directory exists
    systemd.tmpfiles.rules = [
      "d /etc/nix 0755 root root -"
    ];
  };
}
