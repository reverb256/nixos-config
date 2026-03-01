# Common Host Defaults - Shared settings for all cluster nodes
{lib, ...}: {
  system.stateVersion = "26.05";
  services.logind.settings.Login.KillUserProcesses = lib.mkDefault false;

  # Use dbus-broker for better performance and reliability
  services.dbus.implementation = "broker";
}
