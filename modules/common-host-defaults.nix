# Common Host Defaults - Shared settings for all cluster nodes
{lib, ...}: {
  system.stateVersion = "26.05";
  services.logind.settings.Login.KillUserProcesses = lib.mkDefault false;

  # Use dbus-daemon (reference implementation) for stability
  # dbus-broker has a race condition bug that causes 40-second timeouts
  # with Plasma 6 notifications on NVIDIA multi-GPU systems
  # Ref: https://github.com/bus1/dbus-broker/issues/304
  services.dbus.implementation = "dbus";
}
