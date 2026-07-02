{
  config,
  lib,
  ...
}: let
  cfg = config.services.garnix;
in {
  options.services.garnix = {
    enable = lib.mkEnableOption "Garnix CI/CD cache configuration";
  };

  config = lib.mkIf cfg.enable {
    nix.settings = {
      narinfo-cache-positive-ttl = 3600;
      substituters = lib.mkOptionDefault ["https://cache.garnix.io"];
      trusted-public-keys = lib.mkOptionDefault [
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      ];
    };

    # TODO: Create the garnix-password secret file at /run/secrets/garnix-password.
    # The file must contain netrc-format content:
    #   machine cache.garnix.io
    #     login reverb256
    #     password <your-password>
    environment.etc."nix/netrc" = {
      source = "/run/secrets/garnix-password";
      mode = "0600";
    };

    systemd.tmpfiles.rules = [
      "d /etc/nix 0755 root root -"
    ];
  };
}
