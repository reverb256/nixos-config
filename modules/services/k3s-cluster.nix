{
  config,
  lib,
  pkgs,
  ...
}: let
  cluster = config.networking.cluster;
  cfg = config.services.k3s-cluster;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mkMerge
    ;

  inherit (lib) mkOptionDefault;

  isServer = cfg.role == "server";

  clusterCIDR = "10.42.0.0/16";
  serviceCIDR = "10.43.0.0/16";
  clusterDNS = "10.43.0.10";

  tlsSans = [
    "${cluster.kubernetes.vip}"
    "${cluster.hosts.zephyr.ip}"
    "${cluster.hosts.nexus.ip}"
    "${cluster.hosts.forge.ip}"
    "${cluster.hosts.sentry.ip}"
    "${cluster.hosts.krash3.ip}"
    "zephyr"
    "nexus"
    "forge"
    "sentry"
    "krash3"
    "kubernetes"
    "kubernetes.default"
    "kubernetes.default.svc"
    "kubernetes.default.svc.cluster.local"
    "cluster.local"
    "localhost"
    "127.0.0.1"
  ];

  disabledComponents = [
    "traefik"
    "metrics-server"
  ];
in {
  options.services.k3s-cluster = {
    enable = mkEnableOption "k3s lightweight Kubernetes cluster";

    role = mkOption {
      type = types.enum [
        "server"
        "agent"
      ];
      default = "agent";
      description = "k3s node role: server (control plane + workloads) or agent (workloads only)";
    };

    clusterInit = mkOption {
      type = types.bool;
      default = false;
      description = "Set true on the first server to bootstrap a new HA cluster with embedded etcd";
    };

    clusterReset = mkOption {
      type = types.bool;
      default = false;
      description = "Set true once to reset cluster (clear corrupted state), then set false";
    };

    serverAddr = mkOption {
      type = types.str;
      default = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      description = "k3s server URL for agents and joining servers (VIP for HA)";
    };

    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "File containing the k3s cluster token (sops-nix secret)";
    };

    nodeIP = mkOption {
      type = types.str;
      default = "";
      description = "IP address to advertise for this node";
    };

    nodeName = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Kubernetes node name (defaults to hostname)";
    };

    flannelIface = mkOption {
      type = types.str;
      default = "eth0";
      description = "Network interface for flannel VXLAN (must have node IP)";
    };

    flannelBackend = mkOption {
      type = types.enum ["vxlan" "host-gw"];
      default = "host-gw";
      description = "Flannel backend to use. host-gw is recommended for single-LAN clusters.";
    };
    nvidia = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Configure NVIDIA containerd runtime for GPU workloads";
      };
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/rancher/k3s";
      description = "k3s data directory for storing state, etcd, etc.";
    };

    secretsEncryptionKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a 32-byte base64-encoded AES key for etcd secrets encryption at rest. All HA servers MUST use the same key. Use sops-nix to distribute.";
    };
  };

  config = mkIf cfg.enable {
    services.k3s = {
      enable = lib.mkDefault true;
      inherit (cfg) role nodeName;
      # k3s version — pin to specific release to avoid surprise upgrades
      # Previous pin: 1.34.5 (1.35.0-1.35.3 had re-exec crash loop on NixOS)
      # Upgraded: 1.35.4 → 1.36.1 (CSI driver fixes, better RBAC support)
      package = let
        k3sBin = pkgs.fetchurl {
          url = "https://github.com/k3s-io/k3s/releases/download/v1.36.1+k3s1/k3s";
          hash = "sha256-pEPbP+mCDNk2F65n5Dhth8FRTB6WzrMPTCeRw5BlZTw=";
        };
      in
        pkgs.runCommand "k3s-with-agent" {
          nativeBuildInputs = [pkgs.installShellFiles];
        } ''
          mkdir -p $out/bin
          cp ${k3sBin} $out/bin/.k3s-wrapped
          chmod +x $out/bin/.k3s-wrapped
          ln -s .k3s-wrapped $out/bin/k3s
          ln -s .k3s-wrapped $out/bin/k3s-agent
          ln -s .k3s-wrapped $out/bin/crictl
          ln -s .k3s-wrapped $out/bin/ctr
          ln -s .k3s-wrapped $out/bin/kubectl
        '';

      clusterInit =
        if isServer
        then cfg.clusterInit
        else false;

      serverAddr =
        if (!isServer || !cfg.clusterInit)
        then cfg.serverAddr
        else "";

      tokenFile =
        if cfg.clusterInit
        then null
        else cfg.tokenFile;

      nodeIP =
        if cfg.nodeIP != ""
        then cfg.nodeIP
        else null;

      disable =
        # --disable flags are only valid for k3s server, not agent
        # NOTE: Do NOT add "network-policy" to disabledComponents.
        # Disabling the NP controller on the server prevents kube-router
        # agents from creating NWPLCY chains, which causes all cross-node
        # pod traffic to be rejected by POD-FW default-deny rules.
        lib.optionals isServer disabledComponents;

      extraFlags =
        lib.optionals isServer (
          [
            "--cluster-cidr=${clusterCIDR}"
            "--service-cidr=${serviceCIDR}"
            "--cluster-dns=${clusterDNS}"
            "--write-kubeconfig-mode=644"
            "--etcd-arg=auto-compaction-mode=periodic"
            "--etcd-arg=auto-compaction-retention=5m"
            "--etcd-snapshot-retention=10"
            "--etcd-snapshot-compress"
            "--etcd-expose-metrics"
            "--kube-controller-manager-arg=terminated-pod-gc-threshold=500"
            "--kube-controller-manager-arg=node-monitor-grace-period=40s"
            "--flannel-backend=${cfg.flannelBackend}"
          ]
          ++ map (san: "--tls-san=${san}") tlsSans
        )
        ++ lib.optional config.hardware.nvidia-common.enable "--node-label=accelerator=nvidia-gpu"
        ++ lib.optional (config.hardware.gpu-compute.rocm.enable or false) "--node-label=gpu=amd"
        # NOTE: do NOT pass --node-external-ip or --kubelet-arg=node-ip here.
        # cfg.nodeIP already flows to k3s via the upstream module's `nodeIP`
        # option (translating to --node-ip=...), and a duplicate node-ip arg
        # caused kubelet to register the same IP twice as InternalIP, which the
        # apiserver rejected (`status.addresses: duplicate value`).
        ++ [
          "--data-dir=${cfg.dataDir}"
          # Flannel backend: use --flannel-backend for servers (cluster-wide).
          # k3s >=1.36 still supports --flannel-backend despite earlier module
          # comments claiming removal. --flannel-conf (agent-level override)
          # does NOT actually affect backend selection on restart — k3s
          # restores the backend from etcd/node annotations.
          # See https://docs.k3s.io/networking/basic-network-options#flannel-options
          "--flannel-iface=${cfg.flannelIface}"
          "--kubelet-arg=authentication-token-webhook=true"
          "--kubelet-arg=authorization-mode=Webhook"
        ]
        ++ lib.optionals (isServer && cfg.secretsEncryptionKeyFile != null) [
          "--kube-apiserver-arg=encryption-provider-config=${cfg.dataDir}/server/cred/encryption-config.yaml"
        ];

      # --flannel-iface=eth0: explicitly bind flannel VXLAN to eth0 so it uses
      # the real node IP (10.1.1.x), not the VIP (10.1.1.100) added by keepalived.
      # Without this, k3s restarts while keepalived is running cause flannel to
      # bind to the VIP, breaking all cross-node pod networking for zephyr.

      containerdConfigTemplate = mkIf cfg.nvidia.enable ''
        {{ template "base" . }}
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
            BinaryName = "${pkgs.nvidia-container-toolkit.tools}/bin/nvidia-container-runtime"
      '';

      extraKubeletConfig = {
        evictionHard = {
          "memory.available" = "100Mi";
          "nodefs.available" = "5%";
          "nodefs.inodesFree" = "5%";
          "imagefs.available" = "5%";
        };
        failSwapOn = false;
      };

      disableAgent = false;
    };

    # NOTE: flannel.conf via environment.etc has been REMOVED. k3s >=1.36
    # still honors --flannel-backend=host-gw directly. The --flannel-conf
    # mechanism was an agent-level override that didn't actually affect
    # backend selection on restart (k3s restores from etcd annotations).

    # Override the broken nvidia-container-toolkit-cdi-generator with a working one
    # that sets LD_LIBRARY_PATH so nvidia-ctk can find libnvidia-ml.so.
    systemd.services.nvidia-container-toolkit-cdi-generator = mkIf cfg.nvidia.enable {
      wantedBy = ["multi-user.target"];
      after = ["systemd-udev-settle.service"];
      path = with pkgs; [nvidia-container-toolkit jq];
      serviceConfig.ExecStart = lib.mkForce (pkgs.writeShellScript "cdi-generate-static" ''
        mkdir -p /var/run/cdi
        cat > /var/run/cdi/nvidia-container-toolkit.json << 'CDispec'
        {
          "cdiVersion": "0.5.0",
          "kind": "nvidia.com/gpu",
          "devices": [
            {
              "name": "0",
              "containerEdits": {
                "deviceNodes": [
                  {"path": "/dev/nvidia0", "type": "c", "major": 195, "minor": 0},
                  {"path": "/dev/dri/card1", "type": "c", "major": 226, "minor": 1},
                  {"path": "/dev/dri/renderD128", "type": "c", "major": 226, "minor": 128}
                ],
                "mounts": [
                  {"hostPath": "${config.hardware.nvidia.package}/lib", "containerPath": "/usr/local/nvidia/lib", "options": ["ro","nosuid","nodev","bind"]},
                  {"hostPath": "${config.hardware.nvidia.package}/lib", "containerPath": "/usr/local/nvidia/lib64", "options": ["ro","nosuid","nodev","bind"]},
                  {"hostPath": "/run/opengl-driver", "containerPath": "/run/opengl-driver", "options": ["ro","nosuid","nodev","bind"]},
                  {"hostPath": "${pkgs.glibc}/lib", "containerPath": "${pkgs.glibc}/lib", "options": ["ro","nosuid","nodev","bind"]},
                  {"hostPath": "${pkgs.glibc}/lib64", "containerPath": "${pkgs.glibc}/lib64", "options": ["ro","nosuid","nodev","bind"]}
                ],
                "env": ["NVIDIA_VISIBLE_DEVICES=0"]
              }
            },
            {
              "name": "1",
              "containerEdits": {
                "deviceNodes": [
                  {"path": "/dev/nvidia1", "type": "c", "major": 195, "minor": 1},
                  {"path": "/dev/dri/card2", "type": "c", "major": 226, "minor": 2},
                  {"path": "/dev/dri/renderD129", "type": "c", "major": 226, "minor": 129}
                ],
                "mounts": [
                  {"hostPath": "${config.hardware.nvidia.package}/lib", "containerPath": "/usr/local/nvidia/lib", "options": ["ro","nosuid","nodev","bind"]},
                  {"hostPath": "${config.hardware.nvidia.package}/lib", "containerPath": "/usr/local/nvidia/lib64", "options": ["ro","nosuid","nodev","bind"]},
                  {"hostPath": "/run/opengl-driver", "containerPath": "/run/opengl-driver", "options": ["ro","nosuid","nodev","bind"]},
                  {"hostPath": "${pkgs.glibc}/lib", "containerPath": "${pkgs.glibc}/lib", "options": ["ro","nosuid","nodev","bind"]},
                  {"hostPath": "${pkgs.glibc}/lib64", "containerPath": "${pkgs.glibc}/lib64", "options": ["ro","nosuid","nodev","bind"]}
                ],
                "env": ["NVIDIA_VISIBLE_DEVICES=1"]
              }
            },
            {
              "name": "all",
              "containerEdits": {
                "deviceNodes": [
                  {"path": "/dev/nvidia0", "type": "c", "major": 195, "minor": 0},
                  {"path": "/dev/nvidia1", "type": "c", "major": 195, "minor": 1},
                  {"path": "/dev/dri/card1", "type": "c", "major": 226, "minor": 1},
                  {"path": "/dev/dri/card2", "type": "c", "major": 226, "minor": 2},
                  {"path": "/dev/dri/renderD128", "type": "c", "major": 226, "minor": 128},
                  {"path": "/dev/dri/renderD129", "type": "c", "major": 226, "minor": 129}
                ],
                "mounts": [
                  {"hostPath": "${config.hardware.nvidia.package}/lib", "containerPath": "/usr/local/nvidia/lib", "options": ["ro","nosuid","nodev","bind"]},
                  {"hostPath": "${config.hardware.nvidia.package}/lib", "containerPath": "/usr/local/nvidia/lib64", "options": ["ro","nosuid","nodev","bind"]},
                  {"hostPath": "/run/opengl-driver", "containerPath": "/run/opengl-driver", "options": ["ro","nosuid","nodev","bind"]},
                  {"hostPath": "${pkgs.glibc}/lib", "containerPath": "${pkgs.glibc}/lib", "options": ["ro","nosuid","nodev","bind"]},
                  {"hostPath": "${pkgs.glibc}/lib64", "containerPath": "${pkgs.glibc}/lib64", "options": ["ro","nosuid","nodev","bind"]}
                ],
                "env": ["NVIDIA_VISIBLE_DEVICES=all"]
              }
            }
          ],
          "containerEdits": {
            "deviceNodes": [
              {"path": "/dev/nvidiactl", "type": "c", "major": 195, "minor": 255},
              {"path": "/dev/nvidia-modeset", "type": "c", "major": 195, "minor": 254},
              {"path": "/dev/nvidia-uvm", "type": "c", "major": 234, "minor": 0},
              {"path": "/dev/nvidia-uvm-tools", "type": "c", "major": 234, "minor": 1}
            ],
            "mounts": [
              {"hostPath": "${config.hardware.nvidia.package}/lib", "containerPath": "/usr/local/nvidia/lib", "options": ["ro","nosuid","nodev","bind"]},
              {"hostPath": "${config.hardware.nvidia.package}/lib", "containerPath": "/usr/local/nvidia/lib64", "options": ["ro","nosuid","nodev","bind"]},
              {"hostPath": "/run/opengl-driver", "containerPath": "/run/opengl-driver", "options": ["ro","nosuid","nodev","bind"]},
              {"hostPath": "${pkgs.glibc}/lib", "containerPath": "${pkgs.glibc}/lib", "options": ["ro","nosuid","nodev","bind"]},
              {"hostPath": "${pkgs.glibc}/lib64", "containerPath": "${pkgs.glibc}/lib64", "options": ["ro","nosuid","nodev","bind"]}
            ],
            "env": ["LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64"]
          }
        }
        CDispec
        echo "Static CDI spec written ($(wc -c < /var/run/cdi/nvidia-container-toolkit.json) bytes)"
      '');
    };

    # CDI spec for GPU isolation on NixOS.
    # nvidia-ctk cdi generate segfaults due to NixOS glibc/cgo issues.
    # The CDI generator service below works around this by setting LD_LIBRARY_PATH.
    # Runtime config sets mode = "cdi" to use CDI instead of legacy nvidia-container-cli.
    environment.etc."nvidia-container-runtime/config.toml" = mkIf cfg.nvidia.enable {
      source = pkgs.writeText "nvidia-container-runtime-config.toml" ''
        [nvidia-container-cli]
          root = "/run/opengl-driver"
          ldconfig = "@/run/current-system/sw/bin/ldconfig"
          no-cgroups = false
          user = "root"

        [nvidia-container-runtime]
          mode = "cdi"
      '';
    };

    networking.firewall = mkMerge [
      {
        allowedTCPPorts = mkOptionDefault (
          [10250]
          ++ lib.optionals isServer [
            6443
            2379
            2380
          ]
        );
        # NodePort range restricted to LAN subnet (10.1.1.0/24) only.
        # Prevents external access to K8s services bypassing Caddy auth.
        # Host-local services (127.0.0.1) still have full NodePort access.
        extraCommands = ''
          # Restrict NodePort access: DROP then ACCEPT from LAN+localhost
          # (INSERT order matters — second -I goes above first, so ACCEPT is evaluated before DROP)
          iptables -I nixos-fw -p tcp --dport 30000:32767 -j DROP 2>/dev/null || true
          iptables -I nixos-fw -p tcp --dport 30000:32767 -s 127.0.0.1 -j nixos-fw-accept 2>/dev/null || true
          iptables -I nixos-fw -p tcp --dport 30000:32767 -s 10.1.1.0/24 -j nixos-fw-accept 2>/dev/null || true
        '';
        allowedUDPPorts = mkOptionDefault (lib.optionals (cfg.flannelBackend == "vxlan") [
          8472 # k3s flannel VXLAN (NOT 4789)
        ]);
      }
    ];

    environment.systemPackages = with pkgs;
      [
        kubernetes
        cri-tools
        iptables
        runc
      ]
      ++ lib.optionals cfg.nvidia.enable [
        nvidia-container-toolkit
        nvidia-container-toolkit.tools
        libnvidia-container # provides nvidia-container-cli needed by the runtime hook
      ];

    programs.bash.shellAliases = {
      k = "kubectl";
      kgp = "kubectl get pods";
      kgs = "kubectl get svc";
      kgd = "kubectl get deploy";
      kga = "kubectl get all";
      kgns = "kubectl get namespaces";
      kgn = "kubectl get nodes";
    };
    programs.fish.shellAliases = {
      k = "kubectl";
      kgp = "kubectl get pods";
      kgs = "kubectl get svc";
      kgd = "kubectl get deploy";
      kga = "kubectl get all";
      kgns = "kubectl get namespaces";
      kgn = "kubectl get nodes";
    };

    systemd.tmpfiles.rules = [
      "d /root/.kube 0700 root root -"
      "L /root/.kube/config - - - - /etc/rancher/k3s/k3s.yaml"
    ];

    systemd.services.k3s = {
      environment.CONTAINERD_NRI_DISABLED = "1";
      # Do NOT block multi-user.target - k3s can take 5+ minutes to start with etcd
      wantedBy = lib.mkForce [];
      # Belt-and-suspenders: start before keepalived at boot (primary fix: --flannel-iface)
      before = lib.mkIf config.services.keepalived.enable ["keepalived.service"];
      # nfs-utils needed for kubelet to mount NFS PVs (mount.nfs binary)
      path = with pkgs; [nfs-utils];
    };

    # Auto-start k3s at boot WITHOUT blocking multi-user.target.
    # k3s is deliberately excluded from multi-user.target (wantedBy = mkForce []) above
    # because server nodes can take 5+ minutes to start etcd and hang the boot path.
    # This boot timer starts k3s shortly after boot completes so it survives reboots.
    # k3s.service already has Restart=always, so once started it stays up.
    # Safe for all roles (agent + server) and decoupled from boot-critical targets.
    systemd.timers.k3s-autostart = {
      description = "Start k3s after boot (decoupled from multi-user.target to avoid blocking boot)";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        Unit = "k3s.service";
      };
    };

    # Delete stale flannel.1 interface so k3s creates it fresh with --flannel-iface=eth0.
    # Without this, k3s reuses the old interface bound to the VIP (10.1.1.100) instead of
    # creating a new one bound to the real eth0 IP (10.1.1.110). This breaks cross-node
    # VXLAN because remote nodes can't route back to the VIP.
    system.activationScripts.k3s-flannel-clean = ''
      if ip link show flannel.1 &>/dev/null; then
        echo "[k3s-flannel-clean] Deleting stale flannel.1 (bound to old IP)..."
        ip link del flannel.1 2>/dev/null || true
        echo "[k3s-flannel-clean] flannel.1 deleted. k3s will create it with --flannel-iface=eth0."
      fi
    '';

    system.activationScripts.k3s-dirs = ''
      mkdir -p ${cfg.dataDir}/agent/etc/containerd
    '';

    # Local container registry (nexus:5000) for cluster-built images.
    # Required for HA pods that need to pull locally-built images on other nodes.
    environment.etc."rancher/k3s/registries.yaml".text = lib.generators.toYAML {} {
      mirrors = {
        "nexus:5000" = {
          endpoint = ["http://nexus:5000"];
        };
      };
      configs = {
        "nexus:5000" = {
          tls = {
            insecure_skip_verify = true;
          };
        };
      };
    };

    # Replace busybox mount with util-linux mount for NFS PV support.
    # k3s bundles busybox mount which does not support NFS protocol.
    # The real util-linux mount calls mount.nfs as a helper.
    system.activationScripts.k3s-fix-mount = lib.stringAfter ["k3s-dirs"] ''
      for aux in ${cfg.dataDir}/data/*/bin/aux; do
        if [ -L "$aux/mount" ] && readlink "$aux/mount" | grep -q busybox; then
          ln -sf ${pkgs.util-linux.mount}/bin/mount "$aux/mount"
        fi
      done
    '';

    # Static route for K3s CNI pods to reach node IPs on other hosts.
    # Without this, pods with hostNetwork=true that get CNI bridge routing
    # cannot reach node IPs on other hosts (flannel VXLAN only handles pod CIDRs).
    systemd.services.k3s-node-route = {
      description = "Add static route for cross-node CNI pod traffic";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
      script = let
        routeScript = pkgs.writeShellScript "k3s-node-route" ''
          IFACE=$(ip route show default 2>/dev/null | awk ${"'"}{print $5}${"'"} | head -1)
          if [ -n "$IFACE" ]; then
            ip route replace ${cluster.subnet} dev "$IFACE" 2>/dev/null || true
          fi
        '';
      in "${routeScript}";
    };
    systemd.timers.k3s-node-route = {
      description = "Ensure node route exists after network changes";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "10s";
        OnUnitActiveSec = "60s";
        AccuracySec = "5s";
      };
    };

    # Clean up stale kube-router nft rules that block cross-node pod traffic.
    systemd.services.k3s-nft-cleanup = {
      description = "Remove stale kube-router nftables rules";
      after = ["k3s.service"];
      bindsTo = ["k3s.service"];
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
      serviceConfig.ExecStart = pkgs.writeShellScript "nft-cleanup" ''
        handle=$(${pkgs.nftables}/bin/nft -a list chain ip filter FORWARD 2>/dev/null | grep "jump KUBE-ROUTER-FORWARD" | grep -oP 'handle \K\d+')
        if [ -n "$handle" ]; then
          ${pkgs.nftables}/bin/nft delete rule ip filter FORWARD handle "$handle" 2>/dev/null || true
        fi
        for chain in $(${pkgs.nftables}/bin/nft list table ip filter 2>/dev/null | grep -oP 'chain KUBE-POD-FW-\S+' | sed 's/chain //'); do
          ${pkgs.nftables}/bin/nft delete chain ip filter "$chain" 2>/dev/null || true
        done
        ${pkgs.nftables}/bin/nft delete chain ip filter KUBE-ROUTER-FORWARD 2>/dev/null || true
      '';
    };

    systemd.services.k3s-network-taint-fix = lib.mkIf isServer {
      description = "Fix NetworkUnavailable taint";
      path = [pkgs.kubectl];
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = pkgs.writeShellScript "fix-network-taint" ''
        export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
        for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
          kubectl patch node "$node" --type=merge \
            -p '{"status":{"conditions":[{"type":"NetworkUnavailable","status":"False","reason":"CNIIsUp","message":"CNI routes active"}]}}' \
            --subresource=status 2>/dev/null || true
          kubectl taint nodes "$node" node.kubernetes.io/network-unavailable:NoSchedule- 2>/dev/null || true
        done
      '';
    };
    systemd.timers.k3s-network-taint-fix = lib.mkIf isServer {
      description = "Periodically fix NetworkUnavailable taint";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "30s";
        AccuracySec = "10s";
      };
    };

    # ── Secrets encryption at rest (etcd) ──────────────────────────
    # Generates a Kubernetes EncryptionConfiguration from a shared AES key
    # on all server nodes. All HA servers MUST use the same key file.
    # Uses aescbc provider with identity fallback for reading unencrypted secrets.
    #
    # Uses pkgs.writeText at build time (avoids heredoc indentation issues)
    # with a placeholder that sed replaces at runtime with the real key.
    systemd.services.k3s-secrets-encryption = let
      encryptionConfigTemplate = pkgs.writeText "encryption-config.yaml" ''
        apiVersion: apiserver.config.k8s.io/v1
        kind: EncryptionConfiguration
        resources:
          - resources:
              - secrets
            providers:
              - aescbc:
                  keys:
                    - name: key1
                      secret: __ENCRYPTION_KEY__
              - identity: {}
      '';
    in mkIf (isServer && cfg.secretsEncryptionKeyFile != null) {
      description = "Generate etcd encryption config for K3s secrets encryption at rest";
      wantedBy = ["k3s.service"];
      before = ["k3s.service"];
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
      path = with pkgs; [coreutils gnused];
      script = ''
        KEY_FILE="${cfg.secretsEncryptionKeyFile}"
        CONFIG_DIR="${cfg.dataDir}/server/cred"
        CONFIG_FILE="$CONFIG_DIR/encryption-config.yaml"

        if [ ! -f "$KEY_FILE" ]; then
          echo "k3s-secrets-encryption: key file $KEY_FILE not found, skipping"
          exit 0
        fi

        KEY_B64=$(head -c 32 "$KEY_FILE" | ${pkgs.coreutils}/bin/base64 -w0)
        if [ -z "$KEY_B64" ]; then
          echo "k3s-secrets-encryption: key file is empty, skipping"
          exit 0
        fi

        mkdir -p "$CONFIG_DIR"
        sed "s/__ENCRYPTION_KEY__/''${KEY_B64}/" ${encryptionConfigTemplate} > "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
        echo "k3s-secrets-encryption: encryption config written to $CONFIG_FILE"
      '';
    };

    # Etcd defragmentation — compaction alone doesn't reclaim disk space.
    # Must defrag periodically. Runs on all servers.
    systemd.services.k3s-etcd-defrag = lib.mkIf isServer {
      description = "Defragment etcd to reclaim disk space after compaction";
      path = with pkgs; [k3s curl];
      serviceConfig.Type = "oneshot";
      script = ''
        ETCD_ENDPOINT="https://127.0.0.1:2379"
        CERT_DIR="${cfg.dataDir}/server/tls/etcd"
        if [ ! -d "$CERT_DIR" ]; then
          echo "etcd TLS dir not found, skipping defrag"
          exit 0
        fi
        curl --cacert "$CERT_DIR/ca.crt" \
             --cert "$CERT_DIR/server.crt" \
             --key "$CERT_DIR/server.key" \
             -s -X POST "$ETCD_ENDPOINT/maintenance/defrag" || true
      '';
    };
    systemd.timers.k3s-etcd-defrag = lib.mkIf isServer {
      description = "Weekly etcd defragmentation";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
