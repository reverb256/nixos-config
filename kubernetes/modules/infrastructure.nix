{
  config,
  lib,
  pkgs,
  ...
}: let
  pssLabels = {
    "pod-security.kubernetes.io/enforce" = "baseline";
    "pod-security.kubernetes.io/audit" = "restricted";
    "pod-security.kubernetes.io/warn" = "restricted";
  };
  nixosClusterMcp = pkgs.callPackage ../../packages/nixos-cluster-mcp {};
in {
  config.kubernetes.objects.none = {
    PriorityClass.high-priority-ai = {
      value = 1000;
      globalDefault = false;
      description = "High priority for AI inference workloads. Preempts mining pods.";
    };
    PriorityClass.low-priority-mining = {
      value = 100;
      globalDefault = false;
      description = "Low priority for cryptocurrency mining. Preempted by AI workloads.";
    };
  };

  config.kubernetes.objects.default = {
    Namespace.default = {
      metadata.labels =
        pssLabels
        // {
          name = "default";
        };
    };
    NetworkPolicy.default-deny-all = {
      metadata.labels.policy = "default-deny";
      spec = {
        podSelector = {};
        policyTypes = [
          "Ingress"
          "Egress"
        ];
      };
    };
    NetworkPolicy.allow-dns = {
      metadata.labels.policy = "allow-dns";
      spec = {
        podSelector = {};
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{namespaceSelector.matchLabels.name = "kube-system";}];
            ports = [
              {
                protocol = "UDP";
                port = 53;
              }
              {
                protocol = "TCP";
                port = 53;
              }
            ];
          }
        ];
      };
    };
    ConfigMap.security-context-defaults = {
      data = {
        runAsUser = "1001";
        runAsGroup = "1001";
        fsGroup = "1001";
        runAsNonRoot = "true";
        allowPrivilegeEscalation = "false";
        readOnlyRootFilesystem = "true";
        seccompProfileType = "RuntimeDefault";
      };
    };
  };

  config.kubernetes.objects.infra = {
    ServiceAccount.kubernetes-mcp = {};
    ClusterRole.kubernetes-mcp.rules = [
      {apiGroups = [""]; resources = ["pods" "pods/log" "namespaces" "nodes" "services" "configmaps" "secrets" "events"]; verbs = ["get" "list" "watch"];}
      {apiGroups = ["apps"]; resources = ["deployments" "statefulsets" "daemonsets" "replicasets"]; verbs = ["get" "list" "watch"];}
      {apiGroups = ["batch"]; resources = ["jobs" "cronjobs"]; verbs = ["get" "list" "watch"];}
      {apiGroups = ["networking.k8s.io"]; resources = ["ingresses" "networkpolicies"]; verbs = ["get" "list" "watch"];}
    ];
    ClusterRoleBinding.kubernetes-mcp = {
      subjects = [{kind = "ServiceAccount"; name = "kubernetes-mcp"; namespace = "infra";}];
      roleRef = {apiGroup = "rbac.authorization.k8s.io"; kind = "ClusterRole"; name = "kubernetes-mcp";};
    };

    # ── Kubernetes MCP Server (SSE) ───────────────────────────────
    Deployment.kubernetes-mcp = {
      metadata.labels.app = "kubernetes-mcp";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "kubernetes-mcp";
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels.app = "kubernetes-mcp";
          };
          spec = {
            nodeName = "nexus";
            serviceAccountName = "kubernetes-mcp";
            containers = {
              _namedlist = true;
              mcp = {
                image = "ghcr.io/containers/kubernetes-mcp-server:v0.0.51";
                imagePullPolicy = "IfNotPresent";
                args = ["--transport" "sse" "--port" "8080" "--toolsets" "core,helm"];
                ports = [{containerPort = 8080; protocol = "TCP";}];
                resources = {
                  requests = {cpu = "100m"; memory = "128Mi";};
                  limits = {cpu = "500m"; memory = "256Mi";};
                };
                livenessProbe = {
                  httpGet = {path = "/"; port = 8080;};
                  initialDelaySeconds = 10;
                  periodSeconds = 30;
                };
              };
            };
          };
        };
      };
    };
    Service.kubernetes-mcp = {
      metadata.labels.app = "kubernetes-mcp";
      spec = {
        type = "ClusterIP";
        ports = [{port = 8080; targetPort = 8080; protocol = "TCP";}];
        selector.app = "kubernetes-mcp";
      };
    };

    # ── NixOS Cluster MCP (SSE) ──────────────────────────────────
    DaemonSet.nixos-cluster-mcp = {
      metadata.labels.app = "nixos-cluster-mcp";
      spec = {
        selector.matchLabels.app = "nixos-cluster-mcp";
        template = {
          metadata = {
            labels.app = "nixos-cluster-mcp";
            annotations."nix-csi/discard" = "true";
          };
          spec = {
            serviceAccountName = "kubernetes-mcp";
            hostNetwork = true;
            tolerations = [
              {key = "node-role.kubernetes.io/control-plane"; operator = "Exists"; effect = "NoSchedule";}
              {key = "workstation"; operator = "Exists";}
              {key = "interactive"; operator = "Exists";}
            ];
            containers = {
              _namedlist = true;
              mcp = {
                image = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
                imagePullPolicy = "IfNotPresent";
                command = ["${lib.getExe nixosClusterMcp}"];
                env = {HOME.value = "/tmp";};
                resources = {
                  requests = {cpu = "50m"; memory = "64Mi";};
                  limits = {cpu = "200m"; memory = "128Mi";};
                };
                volumeMounts = {
                  _namedlist = true;
                  nix = {mountPath = "/nix"; readOnly = true;};
                  etc-nixos = {mountPath = "/etc/nixos"; readOnly = true;};
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix.hostPath = {path = "/nix"; type = "Directory";};
              etc-nixos.hostPath = {path = "/etc/nixos"; type = "Directory";};
            };
          };
        };
      };
    };
  };
}
