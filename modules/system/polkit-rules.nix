# PolKit rules for NixOS.
#
# System-service management is intentionally not granted globally. Host-specific
# desktop controls must name the exact units they are allowed to manage (for
# example Zephyr's GPU workload menu), rather than turning wheel membership into
# a blanket passwordless systemd API.
_: {
  security.polkit.extraConfig = ''
    // User services do not require polkit; system services are governed by
    // host-specific rules in the owning host configuration.
  '';
}
