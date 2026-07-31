# chronyd.nix — Cluster-wide NTP synchronization via chrony
#
# Issue #246: Clock drift caused etcd leader election failures and
# k3s instability. This module provides aggressive time correction
# with static NTP server IPs (avoids DNS resolution failures during
# network issues).
#
# Deployed on all 4 cluster nodes. chrony replaces systemd-timesyncd.
{ config, lib, pkgs, ... }:
{
  # Disable systemd-timesyncd (chrony replaces it)
  services.timesyncd.enable = lib.mkForce false;

  services.chrony = {
    enable = true;

    # Static NTP server IPs (Cloudflare + Google)
    # Using IPs avoids DNS resolution failures during network issues
    servers = [];
    server = [
      "162.159.200.1 iburst"   # Cloudflare NTP
      "162.159.200.123 iburst" # Cloudflare NTP
      "216.239.35.0 iburst"    # Google NTP
      "216.239.35.4 iburst"    # Google NTP
    ];

    # Aggressive initial correction: step the clock if offset > 1ms
    # on first sync, then allow 100ms steps thereafter
    makestep = {
      enabled = true;
      threshold = 0.1;  # 100ms
      limit = 1;        # Only first sync
    };

    # Allow large initial correction (up to 1 second)
    initstepthreshold = 1.0;

    # Drift file for stable corrections between syncs
    driftfile = "/var/lib/chrony/drift";

    # Real-time scheduling for better accuracy
    realTimeScheduling = true;

    # Log changes
    extraConfig = ''
      logchange 0.1
      logdir /var/log/chrony
    '';
  };
}
