{ config, lib, pkgs, ... }:

{
  nix.settings = {
    max-jobs = 1;
    cores = 1;
    # Disable remote SSH builders — they fail with SSH key/permission issues
    builders = lib.mkDefault [ ];
  };
}
