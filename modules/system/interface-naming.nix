# Consistent Network Interface Naming
# Renames all primary ethernet interfaces to 'lan0' across cluster nodes
{...}: {
  # ============================================================================
  # SYSTEMD NETWORK LINKS - Persistent Interface Naming
  # ============================================================================
  # Uses MAC address matching to ensure consistent naming regardless of
  # whether systemd's predictive naming produces enp*, eno*, or eth*
  systemd.network.links = {
    # ZEPHYR (10.1.1.110) - enp38s0 → lan0
    "10-lan0-zephyr" = {
      matchConfig.MACAddress = "2c:f0:5d:a1:b8:ef";
      linkConfig.Name = "lan0";
    };

    # NEXUS (10.1.1.120) - enp7s0 → lan0
    "10-lan0-nexus" = {
      matchConfig.MACAddress = "e0:d5:5e:a7:4b:50";
      linkConfig.Name = "lan0";
    };

    # FORGE (10.1.1.130) - eno1 → lan0
    "10-lan0-forge" = {
      matchConfig.MACAddress = "30:9c:23:ad:98:d1";
      linkConfig.Name = "lan0";
    };

    # SENTRY (10.1.1.140) - enp7s0 → lan0
    "10-lan0-sentry" = {
      matchConfig.MACAddress = "70:85:c2:d2:87:bf";
      linkConfig.Name = "lan0";
    };
  };
}
