{
  config,
  lib,
  ...
}: let
  cfg = config.services.k3s-cluster;
  sentinelFile = "/var/lib/rancher/k3s/server/.etcd-cleaned";
  etcdDataDir = "/var/lib/rancher/k3s/server/db/etcd";
in {
  config = lib.mkIf (cfg.enable && cfg.etcdClean) {
    systemd.services.k3s-etcd-clean = {
      description = "Clean stale etcd data and rejoin cluster";
      before = ["k3s.service"];
      wantedBy = ["multi-user.target"];
      script = ''
        if [ -f "${sentinelFile}" ]; then
          echo "etcd already cleaned — skipping"
          exit 0
        fi
        echo "=== Stopping k3s for etcd data cleanup ==="
        systemctl stop k3s || true
        if [ -d "${etcdDataDir}" ]; then
          echo "Removing stale etcd data: ${etcdDataDir}"
          rm -rf "${etcdDataDir}"
          echo "etcd data removed"
        else
          echo "No stale etcd data found"
        fi
        echo "Writing sentinel: ${sentinelFile}"
        touch "${sentinelFile}"
        echo "=== Done. k3s will rejoin cluster on next start ==="
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
