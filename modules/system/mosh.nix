{
  pkgs,
  lib,
  ...
}: {
  environment.systemPackages = with pkgs; [mosh];

  networking.firewall.allowedUDPPorts = lib.mkOptionDefault [60000 61000];
}
