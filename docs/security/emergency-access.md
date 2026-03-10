# Emergency Access Procedures

## Scenario: Tailscale Service Down

### Symptoms
- Cannot SSH via Tailscale
- `tailscale status` fails
- Services unreachable via Tailscale IPs

### Recovery Steps

1. **Physical console access**
   - Connect monitor and keyboard to affected host
   - Login with local user account

2. **Restart Tailscale**
   ```bash
   sudo systemctl restart tailscaled
   ```

3. **Check Tailscale status**
   ```bash
   sudo tailscale status
   ```

4. **If still down, check network**
   ```bash
   ip a
   ping 10.1.1.1  # Gateway
   ```

5. **Fallback: Local network access**
   - Connect to local network (10.1.1.0/24)
   - SSH directly to host IP:
     ```bash
     ssh j_kro@10.1.1.110  # Zephyr
     ```

## Scenario: Kubernetes Control Plane Unreachable

### Symptoms
- `kubectl get nodes` fails
- Cannot access cluster services
- API server unreachable

### Recovery Steps

1. **Check control plane status**
   ```bash
   sudo systemctl status kube-apiserver
   sudo systemctl status etcd
   ```

2. **Restart control plane**
   ```bash
   sudo systemctl restart kube-apiserver
   sudo systemctl restart etcd
   ```

3. **Check etcd health**
   ```bash
   sudo etcdctl endpoint health --endpoints=http://10.1.1.110:2379
   ```

4. **Restore from backup if needed**
   ```bash
   # Follow etcd restore procedure
   sudo etcdctl snapshot restore /backup/etcd-snapshot.db
   ```

## Scenario: Storage Failure

### Symptoms
- Services cannot access persistent data
- Mount errors in logs
- High disk usage on /tmp

### Recovery Steps

1. **Check storage status**
   ```bash
   df -h
   mount | grep nfs
   ```

2. **Restart NFS services**
   ```bash
   sudo systemctl restart nfs-client.target
   ```

3. **Manual mount if needed**
   ```bash
   sudo mount -t nfs 10.1.1.120:/data /var/lib/nfs-data
   ```

## Emergency Contacts

- Primary Admin: j_kro
- Backup Location: Local console access only
- Documentation: /etc/nixos/docs/security/
