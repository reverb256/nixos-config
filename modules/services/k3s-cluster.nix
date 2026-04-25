{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.k3s-cluster;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mkMerge
    mkDefault
    ;

  inherit (lib) mkOptionDefault;

  isServer = cfg.role == "server";

  clusterCIDR = "10.244.0.0/16";
  serviceCIDR = "10.0.0.0/12";
  clusterDNS = "10.0.0.10";

  tlsSans = [
    "10.1.1.100"
    "10.1.1.110"
    "10.1.1.120"
    "10.1.1.130"
    "10.1.1.140"
    "zephyr"
    "nexus"
    "forge"
    "sentry"
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
    "servicelb"
    "metrics-server"
  ];

in
{
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
      default = "https://10.1.1.100:6443";
      description = "k3s server URL for agents and joining servers (VIP for HA)";
    };

    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "File containing the k3s cluster token (agenix secret)";
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

    calico = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Use Calico CNI. Disables flannel, network-policy, and kube-proxy.";
      };
    };

    nvidia = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Configure NVIDIA containerd runtime for GPU workloads";
      };
    };
  };

  config = mkIf cfg.enable {
    services.k3s = {
      enable = true;
      inherit (cfg) role nodeName;

      # k3s agent mode re-execs itself via /proc/self/exe as "k3s-agent",
      # but the Nix package doesn't ship that name. We must copy the real
      # Go binary (.k3s-wrapped) directly — NOT the C wrapper — so that
      # /proc/self/exe resolves to our $out/bin/ where both "k3s" and
      # "k3s-agent" exist as copies of the same binary.
      # The C wrapper is skipped because: (1) it has a hardcoded path to
      # .k3s-wrapped in the raw package dir, breaking /proc/self/exe, and
      # (2) systemd already sets PATH for the service.
      package = pkgs.runCommand "k3s-with-agent-symlink" {} ''
        mkdir -p $out/bin
        # Copy the real Go binary as both k3s and k3s-agent
        cp ${pkgs.k3s_1_34}/bin/.k3s-wrapped $out/bin/k3s
        cp ${pkgs.k3s_1_34}/bin/.k3s-wrapped $out/bin/k3s-agent
        chmod +x $out/bin/k3s $out/bin/k3s-agent
        # Symlink any other binaries from the package (kubectl, crictl, etc.)
        for f in ${pkgs.k3s_1_34}/bin/*; do
          local name=$(basename "$f")
          if [ "$name" != ".k3s-wrapped" ] && [ "$name" != "k3s" ] && [ ! -e "$out/bin/$name" ]; then
            ln -sf "$f" "$out/bin/$name"
          fi
        done
      '';

      clusterInit = if isServer then cfg.clusterInit else false;

      serverAddr = if (!isServer || !cfg.clusterInit) then cfg.serverAddr else "";

      tokenFile = if cfg.clusterInit then null else cfg.tokenFile;

      nodeIP = if cfg.nodeIP != "" then cfg.nodeIP else null;

      disable =
        lib.optionals isServer disabledComponents
        ++ lib.optionals (isServer && cfg.calico.enable) [
          "flannel"
          "network-policy"
          "kube-proxy"
        ];

      extraFlags =
        lib.optionals isServer (
          [
            "--cluster-cidr=${clusterCIDR}"
            "--service-cidr=${serviceCIDR}"
            "--cluster-dns=${clusterDNS}"
            "--write-kubeconfig-mode=644"
          ]
          ++ map (san: "--tls-san=${san}") tlsSans
          ++ lib.optional cfg.calico.enable "--flannel-backend=none"
        )
        ++ lib.optional config.hardware.nvidia-common.enable "--node-label=accelerator=nvidia-gpu"
        ++ lib.optional (config.hardware.gpu-compute.rocm.enable or false) "--node-label=gpu=amd"
        ++ lib.optional (cfg.nodeIP != "") "--node-external-ip=${cfg.nodeIP}"
        ++ [
          "--kubelet-arg=authentication-token-webhook=true"
          "--kubelet-arg=authorization-mode=Webhook"
        ];
        # --flannel-external-ip removed in k3s 1.34+ (upstream PR)
        # Flannel now auto-detects external IP from --node-external-ip

      containerdConfigTemplate = mkIf cfg.nvidia.enable ''
        {{ template "base" . }}
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
            BinaryName = "${pkgs.nvidia-container-toolkit.tools}/bin/nvidia-container-runtime"
      '';

      extraKubeletConfig = {
        failSwapOn = false;
      };

      disableAgent = false;
    };

    # Override the broken nvidia-container-toolkit-cdi-generator with a working one
    # that sets LD_LIBRARY_PATH so nvidia-ctk can find libnvidia-ml.so.
    systemd.services.nvidia-container-toolkit-cdi-generator = mkIf cfg.nvidia.enable {
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-udev-settle.service" ];
      path = with pkgs; [ nvidia-container-toolkit jq ];
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
          [ 10250 ]
          ++ lib.optionals isServer [
            6443
            2379
            2380
          ]
          ++ lib.optionals cfg.calico.enable [
            179
            5473
          ]
        );
        allowedTCPPortRanges = [
          {
            from = 30000;
            to = 32767;
          }
        ];
        allowedUDPPorts = mkOptionDefault (
          lib.optionals (!cfg.calico.enable) [
            8472
          ]
          ++ [
            4789
          ]
        );
      }
    ];

    environment.systemPackages =
      with pkgs;
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
      # Start before keepalived so flannel detects the real IP, not the VIP
      before = lib.mkIf config.services.keepalived.enable [ "keepalived.service" ];
    };

    system.activationScripts.k3s-dirs = ''
      mkdir -p /var/lib/rancher/k3s/agent/etc/containerd
    '';

    # Static route for K3s CNI pods to reach node IPs on other hosts.
    # Without this, pods with hostNetwork=true that get CNI bridge routing
    # cannot reach node IPs on other hosts (flannel VXLAN only handles pod CIDRs).
    systemd.services.k3s-node-route = {
      description = "Add static route for cross-node CNI pod traffic";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
      script = let
        routeScript = pkgs.writeShellScript "k3s-node-route" ''
          IFACE=$(ip route show default 2>/dev/null | awk ${"'"}{print $5}${"'"} | head -1)
          if [ -n "$IFACE" ]; then
            ip route replace 10.1.1.0/24 dev "$IFACE" 2>/dev/null || true
          fi
        '';
      in "${routeScript}";
    };
    systemd.timers.k3s-node-route = {
      description = "Ensure node route exists after network changes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10s";
        OnUnitActiveSec = "60s";
        AccuracySec = "5s";
      };
    };

    systemd.services.k3s-network-taint-fix = lib.mkIf isServer {
      description = "Fix NetworkUnavailable taint";
      path = [ pkgs.kubectl ];
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
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "30s";
        AccuracySec = "10s";
      };
    };
  };
}
