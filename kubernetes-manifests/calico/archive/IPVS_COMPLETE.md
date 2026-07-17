# IPVS Implementation Complete (Task 14)

**Status:** ✅ COMPLETE (2026-03-24)
**Node:** Zephyr (control plane)
**Mode:** IPVS (IP Virtual Server) for kube-proxy

## Implementation Summary

### Changes Made

1. **Modified `/etc/nixos/modules/services/kubernetes.nix`:**
   - Added `calicoIpvs` configuration options (enable, autoHostRanges, strictArp)
   - Added IPVS kernel module loading (ip_vs, ip_vs_rr, ip_vs_wrr, ip_vs_sh, nf_conntrack)
   - Added ipvsadm, ipset, and kmod to system packages
   - Configured kube-proxy to use IPVS mode with proper flags
   - Added systemd service override to include ipset/kmod in kube-proxy PATH

2. **Modified `/etc/nixos/hosts/zephyr/configuration.nix`:`
   - Enabled calicoIpvs for Zephyr control plane node

3. **Created verification script:** `/etc/nixos/kubernetes-manifests/calico/verify-ipvs.sh`

## Verification Results

### ✅ IPVS Kernel Modules Loaded
```
ip_vs_wrr              16384  0
ip_vs_sh               16384  0
ip_vs_rr               12288  46
ip_vs                 233472  52
nf_conntrack          196608  7
```

### ✅ kube-proxy Using IPVS Mode
```
Mar 24 10:20:41 zephyr kube-proxy[3445234]: "Using ipvs Proxier"
```

### ✅ IPVS Virtual Services Active
- 30+ Kubernetes services managed by IPVS
- Round-robin scheduling (rr) configured
- Services include: CoreDNS, Caddy, Prometheus, Grafana, and all cluster workloads

## Performance Benefits

- **O(1) lookup** vs O(n) iptables for service load balancing
- **Better scalability** for high-service-count clusters
- **Lower latency** for service-to-service communication
- **Automatic failover** and load distribution

## Configuration Details

### kube-proxy IPVS Flags
```bash
--proxy-mode=ipvs
--ipvs-scheduler=rr
--ipvs-min-sync-period=1s
--ipvs-sync-period=10s
--ipvs-strict-arp=true
```

### IPVS Services Sample
```
TCP  10.0.0.10:53 rr              # CoreDNS
  -> 10.244.98.57:53              Masq    1      0          0
TCP  10.0.0.43:9090 rr            # Caddy metrics
  -> 10.1.1.110:9090              Masq    1      0          0
TCP  10.0.0.170:3333 rr persistent 10800  # Mining proxy
  -> 10.1.1.120:3333              Masq    1      1          0
```

## Next Steps

1. **Monitor performance:** Compare service-to-service latency before/after IPVS
2. **Expand to other nodes:** Enable IPVS on Nexus, Forge, Sentry if performance gains are significant
3. **Consider nftables:** Kubernetes deprecated IPVS in favor of nftables (future migration)

## Troubleshooting

### Check IPVS status
```bash
sudo ipvsadm -Ln              # List virtual servers
sudo ipvsadm -Ln --rate       # Show connection rates
lsmod | grep ip_vs            # Verify modules loaded
```

### Check kube-proxy mode
```bash
journalctl -u kube-proxy | grep "Using.*Proxier"
```

### Restart kube-proxy
```bash
sudo systemctl restart kube-proxy
```

## References

- **IPVS docs:** https://kernel.org/doc/Documentation/networking/ipvs-sysctl.txt
- **kube-proxy IPVS:** https://kubernetes.io/docs/tasks/administer-cluster/kube-proxy/
- **Calico + IPVS:** https://docs.projectcalico.org/reference/felix/configuration

## Files Created/Modified

- `/etc/nixos/modules/services/kubernetes.nix` (IPVS configuration, kernel modules, PATH override)
- `/etc/nixos/hosts/zephyr/configuration.nix` (enabled calicoIpvs)
- `/etc/nixos/kubernetes-manifests/calico/verify-ipvs.sh` (verification script)
- `/etc/nixos/kubernetes-manifests/calico/IPVS_COMPLETE.md` (this document)
