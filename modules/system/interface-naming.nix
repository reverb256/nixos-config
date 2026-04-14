_: {
  systemd.network.links = {
    "10-lan0-zephyr" = {
      matchConfig.MACAddress = "2c:f0:5d:a1:b8:ef";
      linkConfig.Name = "lan0";
    };

    "10-lan0-nexus" = {
      matchConfig.MACAddress = "00:0e:c6:c6:16:67";
      linkConfig.Name = "lan0";
    };

    "10-lan0-forge" = {
      matchConfig.MACAddress = "30:9c:23:ad:98:d1";
      linkConfig.Name = "lan0";
    };

    "10-lan0-sentry" = {
      matchConfig.MACAddress = "70:85:c2:d2:87:bf";
      linkConfig.Name = "lan0";
    };
  };
}
