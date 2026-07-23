# Cilium host sysctl overrides.
#
# Cilium's CNI datapath needs rp_filter disabled on its veth/interfaces
# so eBPF datapath traffic isn't dropped by asymmetric-path filtering.
# Previously a hand-placed /etc/sysctl.d/99-zzz-override_cilium.conf covered
# this; migrated here so it lives in the declarative source of truth.
#
# Note on wildcards (sysctl doesn't support them in keys): we set
# `all.rp_filter = 0` and `default.rp_filter = 0` so that newly-created
# veth interfaces (Cilium-managed, LXD-managed, anything else) inherit
# rp_filter=0 transitively via the kernel's `max(conf.all, conf.<dev>)`
# policy. Wildcard keys like `lxc*` or `cilium_*` would NOT match any
# path under /proc/sys/net/ipv4/conf/ and would error out at sysctl -w.
{ lib, ... }:
{
  boot.extraSysctls = {
    # kernel-everywhere default (max wins over per-device)
    "net.ipv4.conf.all.rp_filter" = 0;
    # per-interface default (covers newly-created interfaces — incl. Cilium veths)
    "net.ipv4.conf.default.rp_filter" = 0;
  };
}
