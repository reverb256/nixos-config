{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.garnix;

  # Garnix credentials for cache.garnix.io
  garnixNetrc = pkgs.writeText "garnix-netrc" ''
    machine cache.garnix.io
      login reverb256
      password EV1t91y48c6CTCkNbezdhJBU2QTdIVPCjE9sSxyY
  '';
in {
  options.services.garnix = {
    enable = lib.mkEnableOption "Garnix CI/CD cache configuration";
  };

  config = lib.mkIf cfg.enable {
    # Nix settings for Garnix cache
    nix.settings = {
      # Reduce TTL for presigned URLs that expire quickly
      narinfo-cache-positive-ttl = 3600;
      # Point to netrc file for authentication
      netrc-file = "/etc/nix/netrc";
      # Add Garnix as a substituter
      substituters = ["https://cache.garnix.io"];
      trusted-public-keys = ["cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="];
    };

    # Create netrc file for Garnix authentication
    environment.etc."nix/netrc" = {
      source = garnixNetrc;
      mode = "0600";
    };

    # Ensure nix config directory exists
    systemd.tmpfiles.rules = [
      "d /etc/nix 0755 root root -"
    ];
  };
}
