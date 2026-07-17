# Mosh (Mobile Shell) - Better SSH for unstable connections
# Provides better connection handling and local echo
{
  pkgs,
  lib,
  ...
}: {
  environment.systemPackages = with pkgs; [mosh];

  # Open mosh UDP ports in firewall (60000-61000)
  # Append to existing firewall configuration
  networking.firewall.allowedUDPPorts = lib.mkOptionDefault [60000 61000];

  # mosh-server is started automatically when needed
  # No service configuration required - uses systemd socket activation
}
