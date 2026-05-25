{ config, pkgs, lib, ... }:

let
  cfg = config.services.etcd-cluster;
  inherit (lib) mkEnableOption mkOption types mkIf;

  openssl = "${pkgs.openssl}/bin/openssl";

  # ── Cluster topology ──────────────────────────────────────────
  cluster = config.networking.cluster;

  members = [
    { name = "etcd-nexus";  ip = cluster.hosts.nexus.ip;  }
    { name = "etcd-forge";  ip = cluster.hosts.forge.ip;  }
    { name = "etcd-sentry"; ip = cluster.hosts.sentry.ip; }
  ];

  hostName = config.networking.hostName;
  selfMember = lib.head (
    builtins.filter (m: m.name == "etcd-${hostName}") members
  );

  initialClusterStr = lib.concatStringsSep "," (
    map (m: "${m.name}=https://${m.ip}:2380") members
  );

  serverSANs = lib.concatStringsSep "," (
    map (m: "IP:${m.ip}") members ++ [ "DNS:localhost" "IP:127.0.0.1" ]
  );

  peerSANs = "IP:${selfMember.ip},DNS:${selfMember.name},DNS:${hostName}";

  tlsDir = "/var/lib/etcd/secrets";

  isEtcdMember = builtins.elem selfMember members;

in {
  options.services.etcd-cluster = {
    enable = mkEnableOption "External HA etcd cluster service";
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/etcd";
      description = "Directory for etcd data (WAL + db)";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = isEtcdMember;
        message = "etcd-cluster: host ${hostName} is not in the etcd member list. "
          + "Members: ${lib.concatStringsSep ", " (map (m: m.name) members)}";
      }
    ];

    services = mkIf isEtcdMember {
      etcd = {
        enable = true;
        name = selfMember.name;
        dataDir = cfg.dataDir;

        initialCluster = initialClusterStr;
        initialClusterToken = "nixos-cluster-etcd-quorum";
        initialClusterState = "new";

        listenPeerUrls = [ "https://${selfMember.ip}:2380" ];
        initialAdvertisePeerUrls = [ "https://${selfMember.ip}:2380" ];

        listenClientUrls = [ "https://${selfMember.ip}:2379" "https://127.0.0.1:2379" ];
        advertiseClientUrls = [ "https://${selfMember.ip}:2379" ];

        # mTLS: Peer authentication
        peerCertAuth = true;
        peerTrustedCaFile = "${tlsDir}/etcd-ca.crt";
        peerCertFile = "${tlsDir}/peer.crt";
        peerKeyFile = "${tlsDir}/peer.key";

        # mTLS: Client authentication
        clientCertAuth = true;
        trustedCaFile = "${tlsDir}/etcd-ca.crt";
        certFile = "${tlsDir}/server.crt";
        keyFile = "${tlsDir}/server.key";

        extraConf = {
          auto-compaction-mode = "periodic";
          auto-compaction-retention = "5m";
          quota-backend-bytes = 8589934592;  # 8 GB
          heartbeat-interval = 250;
          election-timeout = 1250;
          snapshot-count = 10000;
        };
      };

      networking.firewall.allowedTCPPorts = [ 2379 2380 ];
    };

    # ── TLS certificate generator ─────────────────────────────
    systemd.services.etcd-tls-setup = mkIf isEtcdMember {
      description = "Generate etcd mTLS certificates";
      wantedBy = [ "etcd.service" ];
      before = [ "etcd.service" ];
      requiredBy = [ "etcd.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        PrivateTmp = true;
      };
      script = ''
        mkdir -p ${tlsDir}
        cd ${tlsDir}

        if [ ! -f etcd-ca.crt ]; then
          ${openssl} genrsa -out etcd-ca.key 4096 2>/dev/null
          ${openssl} req -x509 -new -key etcd-ca.key -out etcd-ca.crt \
            -days 3650 -nodes \
            -subj "/C=CA/ST=Ontario/O=Cluster/CN=etcd CA" \
            -addext "basicConstraints=critical,CA:TRUE" \
            -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
          chmod 640 etcd-ca.key
          chmod 644 etcd-ca.crt
          echo "etcd CA generated"
        fi

        if [ ! -f peer.crt ]; then
          ${openssl} genrsa -out peer.key 2048 2>/dev/null
          ${openssl} req -new -key peer.key -out /tmp/peer.csr \
            -subj "/CN=${selfMember.name}" \
            -addext "subjectAltName=${peerSANs}" 2>/dev/null
          ${openssl} x509 -req -in /tmp/peer.csr \
            -CA etcd-ca.crt -CAkey etcd-ca.key -CAcreateserial \
            -out peer.crt -days 365 -copy_extensions copyall 2>/dev/null
          rm -f /tmp/peer.csr
          chmod 640 peer.key
          chmod 644 peer.crt
          echo "Peer cert for ${selfMember.name}"
        fi

        if [ ! -f server.crt ]; then
          ${openssl} genrsa -out server.key 2048 2>/dev/null
          ${openssl} req -new -key server.key -out /tmp/server.csr \
            -subj "/CN=etcd-cluster" \
            -addext "subjectAltName=${serverSANs}" 2>/dev/null
          ${openssl} x509 -req -in /tmp/server.csr \
            -CA etcd-ca.crt -CAkey etcd-ca.key -CAcreateserial \
            -out server.crt -days 365 -copy_extensions copyall 2>/dev/null
          rm -f /tmp/server.csr
          chmod 640 server.key
          chmod 644 server.crt
          echo "Server cert generated"
        fi

        if [ ! -f k3s-client.crt ]; then
          ${openssl} genrsa -out k3s-client.key 2048 2>/dev/null
          ${openssl} req -new -key k3s-client.key -out /tmp/k3s.csr \
            -subj "/CN=k3s-client" \
            -addext "subjectAltName=DNS:k3s-client" 2>/dev/null
          ${openssl} x509 -req -in /tmp/k3s.csr \
            -CA etcd-ca.crt -CAkey etcd-ca.key -CAcreateserial \
            -out k3s-client.crt -days 365 -copy_extensions copyall 2>/dev/null
          rm -f /tmp/k3s.csr
          chmod 640 k3s-client.key
          chmod 644 k3s-client.crt
          echo "K3s client cert generated"
        fi

        chown -R root:root ${tlsDir}
      '';
    };

    # ── Systemd tuning for etcd ────────────────────────────
    systemd.services.etcd = mkIf isEtcdMember {
      after = [ "etcd-tls-setup.service" ];
      wants = [ "etcd-tls-setup.service" ];
      serviceConfig = {
        LimitNOFILE = 65536;
        CPUSchedulingPolicy = "rr";
        CPUSchedulingPriority = 99;
        IOSchedulingPriority = 1;
      };
    };

    environment.systemPackages = mkIf isEtcdMember [ pkgs.etcd ];
  };
}
