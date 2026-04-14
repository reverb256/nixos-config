{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.garnix;

  garnixNetrc = pkgs.writeText "garnix-netrc" ''
    machine cache.garnix.io
      login reverb256
      password TvENbzJlSFCUqJhsP+l575OwKcTVFp32+8Fhzkk1
  '';
in {
  options.services.garnix = {
    enable = lib.mkEnableOption "Garnix CI/CD cache configuration";
  };

  config = lib.mkIf cfg.enable {
    nix.settings = {
      narinfo-cache-positive-ttl = 3600;
      substituters = lib.mkOptionDefault ["https://cache.garnix.io"];
      trusted-public-keys = lib.mkOptionDefault ["cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="];
    };

    environment.etc."nix/netrc" = {
      source = garnixNetrc;
      mode = "0600";
    };

    systemd.tmpfiles.rules = [
      "d /etc/nix 0755 root root -"
    ];
  };
}
