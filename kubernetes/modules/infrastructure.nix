{
  config,
  lib,
  pkgs,
  nexusPreferredAffinity,
  ...
}: let
  pssLabels = {
    "pod-security.kubernetes.io/enforce" = "baseline";
    "pod-security.kubernetes.io/audit" = "restricted";
    "pod-security.kubernetes.io/warn" = "restricted";
  };
  nixosClusterMcp = pkgs.callPackage ../../packages/nixos-cluster-mcp {};
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects.none = {
    # ── Require security context on all pods (Deny mode) ───────────
    # Prevents pods without runAsNonRoot, allowPrivilegeEscalation=false, and resource limits
    ValidatingAdmissionPolicy.require-resources-and-security = {
      metadata.annotations = {
        "description" = "Requires all containers to define runAsNonRoot=true, no privilege escalation, and resource limits";
      };
      spec = {
        failurePolicy = "Fail";
        matchConstraints = {
          resourceRules = [
            {
              apiGroups = [""];
              apiVersions = ["v1"];
              operations = ["CREATE" "UPDATE"];
              resources = ["pods"];
            }
          ];
        };
        validations = [
          {
            expression = "object.spec.containers.all(c, has(c.resources.limits) && has(c.resources.limits.cpu) && has(c.resources.limits.memory))";
            message = "All containers must specify CPU and memory limits in resources.limits";
          }
          {
            expression = "object.spec.containers.all(c, has(c.resources.requests) && has(c.resources.requests.cpu) && has(c.resources.requests.memory))";
            message = "All containers must specify CPU and memory requests in resources.requests";
          }
          {
            expression = "object.spec.containers.all(c, has(c.securityContext) && c.securityContext.runAsNonRoot == true)";
            message = "All containers must run as non-root (securityContext.runAsNonRoot: true)";
          }
          {
            expression = "object.spec.containers.all(c, !has(c.securityContext.allowPrivilegeEscalation) || c.securityContext.allowPrivilegeEscalation == false)";
            message = "Containers must not allow privilege escalation (securityContext.allowPrivilegeEscalation: false)";
          }
        ];
      };
    };

    # ── NFS Client StorageClass ──────────────────────────────────
    # Backed by the nfs-subdir-external-provisioner on nexus.
    # NFS exports: /data/hermes, /data/pi, /data/qdrant, /etc/nixos
    StorageClass.nfs-client = {
      metadata.annotations."storageclass.kubernetes.io/is-default-class" = "true";
      provisioner = "nfs-client";
      parameters = {
        archiveOnDelete = "true";
      };
      mountOptions = ["vers=4.1" "hard" "noatime"];
      reclaimPolicy = "Delete";
      volumeBindingMode = "Immediate";
    };
    ValidatingAdmissionPolicyBinding.require-resources-and-security = {
      spec = {
        policyName = "require-resources-and-security";
        validationActions = ["Deny"];
        matchResources = {
          namespaceSelector.matchExpressions = [
            {
              key = "kubernetes.io/metadata.name";
              operator = "NotIn";
              values = [
                "kube-system"
                "kube-public"
                "kube-node-lease"
                "ai-inference"
                "tailscale"
                "nix-csi"
              ];
            }
          ];
        };
      };
    };

    PriorityClass.high-priority-ai = {
      value = 1000;
      globalDefault = false;
      description = "High priority for AI inference workloads. Preempts mining pods.";
    };
    PriorityClass.medium-priority-ai = {
      value = 500;
      globalDefault = false;
      description = "Medium priority for AI workloads (Nexus RTX 3060 Ti). Lower than high-priority AI, above mining.";
    };
    PriorityClass.low-priority-mining = {
      value = 100;
      globalDefault = false;
      description = "Low priority for cryptocurrency mining. Preempted by AI workloads.";
    };

    # ── Require resource limits on all pods ──────────────────────
    # Audit mode: warns but does not block. Lets us find non-compliant workloads first.
    ValidatingAdmissionPolicy.require-resource-limits = {
      metadata.annotations = {
        "description" = "Requires all containers to define resource requests and limits (cpu, memory)";
      };
      spec = {
        failurePolicy = "Fail";
        matchConstraints = {
          resourceRules = [
            {
              apiGroups = [""];
              apiVersions = ["v1"];
              operations = ["CREATE" "UPDATE"];
              resources = ["pods"];
            }
          ];
        };
        validations = [
          {
            expression = "self.containers.all(c, has(c.resources) && has(c.resources.requests) && has(c.resources.limits) && has(c.resources.requests.cpu) && has(c.resources.requests.memory) && has(c.resources.limits.cpu) && has(c.resources.limits.memory))";
            message = "Every container must define resources.requests and resources.limits with cpu and memory";
          }
          {
            expression = "self.initContainers.all(c, has(c.resources) && has(c.resources.requests) && has(c.resources.limits) && has(c.resources.requests.cpu) && has(c.resources.requests.memory) && has(c.resources.limits.cpu) && has(c.resources.limits.memory))";
            message = "Every initContainer must define resources.requests and resources.limits with cpu and memory";
          }
        ];
      };
    };
    ValidatingAdmissionPolicyBinding.require-resource-limits = {
      spec = {
        policyName = "require-resource-limits";
        validationActions = ["Audit"];
        matchResources = {
          namespaceSelector.matchExpressions = [
            {
              key = "kubernetes.io/metadata.name";
              operator = "Exists";
            }
          ];
        };
      };
    };
    Namespace.ingress-system = {
      metadata.labels =
        managed
        // {
          name = "ingress-system";
          "pod-security.kubernetes.io/enforce" = "baseline";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        };
    };

    # ── Pod Security Standards labels on all namespaces ────────────
    # System namespaces keep privileged enforcement; everything else
    # enforces baseline with restricted audit/warn.
    Namespace.ai-coding.metadata.labels = pssLabels // {name = "ai-coding";};
    Namespace.ai-inference.metadata.labels = pssLabels // {name = "ai-inference";};
    Namespace.auth.metadata.labels = pssLabels // {name = "auth";};
    Namespace.automation.metadata.labels = pssLabels // {name = "automation";};
    Namespace.cert-manager.metadata.labels = pssLabels // {name = "cert-manager";};
    Namespace.custom-metrics.metadata.labels = pssLabels // {name = "custom-metrics";};
    Namespace.dashboard.metadata.labels = pssLabels // {name = "dashboard";};
    Namespace.kagent.metadata.labels = pssLabels // {name = "kagent";};
    Namespace.kelos-system.metadata.labels = pssLabels // {name = "kelos-system";};
    Namespace.maplespike-dev.metadata.labels = pssLabels // {name = "maplespike-dev";};
    Namespace.maplespike-prod.metadata.labels = pssLabels // {name = "maplespike-prod";};
    Namespace.mining.metadata.labels = pssLabels // {name = "mining";};
    Namespace.monitoring.metadata.labels = pssLabels // {name = "monitoring";};
    Namespace.nixkube.metadata.labels = pssLabels // {name = "nixkube";};
    Namespace.orchestration.metadata.labels = pssLabels // {name = "orchestration";};
    Namespace.search.metadata.labels = pssLabels // {name = "search";};
    Namespace.tailscale.metadata.labels = pssLabels // {name = "tailscale";};
    Namespace.vaultwarden.metadata.labels = pssLabels // {name = "vaultwarden";};
    Namespace.kube-system.metadata.labels = {
      name = "kube-system";
      "pod-security.kubernetes.io/enforce" = "privileged";
      "pod-security.kubernetes.io/audit" = "baseline";
      "pod-security.kubernetes.io/warn" = "restricted";
    };
    Namespace.kube-public.metadata.labels = {
      name = "kube-public";
      "pod-security.kubernetes.io/enforce" = "privileged";
      "pod-security.kubernetes.io/audit" = "baseline";
      "pod-security.kubernetes.io/warn" = "restricted";
    };
    Namespace.kube-node-lease.metadata.labels = {
      name = "kube-node-lease";
      "pod-security.kubernetes.io/enforce" = "privileged";
      "pod-security.kubernetes.io/audit" = "baseline";
      "pod-security.kubernetes.io/warn" = "restricted";
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
      metadata.labels = managed // {policy = "default-deny";};
      spec = {
        podSelector = {};
        policyTypes = [
          "Ingress"
          "Egress"
        ];
      };
    };
    NetworkPolicy.allow-dns = {
      metadata.labels = managed // {policy = "allow-dns";};
      spec = {
        podSelector = {};
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";}];
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
      {
        apiGroups = [""];
        resources = ["pods" "pods/log" "namespaces" "nodes" "services" "configmaps" "secrets" "events"];
        verbs = ["get" "list" "watch"];
      }
      {
        apiGroups = ["apps"];
        resources = ["deployments" "statefulsets" "daemonsets" "replicasets"];
        verbs = ["get" "list" "watch"];
      }
      {
        apiGroups = ["batch"];
        resources = ["jobs" "cronjobs"];
        verbs = ["get" "list" "watch"];
      }
      {
        apiGroups = ["networking.k8s.io"];
        resources = ["ingresses" "networkpolicies"];
        verbs = ["get" "list" "watch"];
      }
      {
        apiGroups = ["metrics.k8s.io"];
        resources = ["nodes" "pods"];
        verbs = ["get" "list" "watch"];
      }
      {
        apiGroups = [""];
        resources = ["persistentvolumes" "persistentvolumeclaims"];
        verbs = ["get" "list" "watch"];
      }
      {
        apiGroups = ["autoscaling"];
        resources = ["horizontalpodautoscalers"];
        verbs = ["get" "list" "watch"];
      }
    ];
    ClusterRoleBinding.kubernetes-mcp = {
      subjects = [
        {
          kind = "ServiceAccount";
          name = "kubernetes-mcp";
          namespace = "infra";
        }
      ];
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "kubernetes-mcp";
      };
    };

    # ── Kubernetes MCP Server (SSE + Streamable HTTP) ─────────────
    # SSE endpoint: GET /sse (legacy)
    # Streamable HTTP endpoint: POST /mcp (recommended for HTTP clients)
    # Health check: GET /healthz
    Deployment.kubernetes-mcp = {
      metadata.labels = managed // {app = "kubernetes-mcp";};
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
            affinity = nexusPreferredAffinity; # HA: prefer nexus, failover to sentry
            serviceAccountName = "kubernetes-mcp";
            containers = {
              _namedlist = true;
              mcp = {
                # Tag pinned to v0.3.0 — check ghcr.io/containers/kubernetes-mcp-server for newer versions
                image = "ghcr.io/containers/kubernetes-mcp-server:v0.3.0-linux-amd64";
                imagePullPolicy = "IfNotPresent";
                args = ["--port" "8080" "--toolsets" "core,helm" "--stateless"];
                ports = [
                  {
                    containerPort = 8080;
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "256Mi";
                  };
                };
                readinessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 8080;
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 8080;
                  };
                  initialDelaySeconds = 15;
                  periodSeconds = 30;
                  failureThreshold = 3;
                };
              };
            };
          };
        };
      };
    };
    Service.kubernetes-mcp = {
      metadata.labels = managed // {app = "kubernetes-mcp";};
      spec = {
        type = "ClusterIP";
        ports = [
          {
            port = 8080;
            targetPort = 8080;
            protocol = "TCP";
          }
        ];
        selector.app = "kubernetes-mcp";
      };
    };
  };

  # ── AMD GPU Device Plugin ────────────────────────────────────
  # Registers AMD GPUs (gpu:amd nodes) with K8s via the ROCm device plugin
  config.kubernetes.objects.kube-system.DaemonSet.amd-gpu-device-plugin = {
    metadata = {
      labels =
        managed
        // {
          app = "amd-gpu-device-plugin";
          name = "amd-gpu-device-plugin-ds";
        };
    };
    spec = {
      selector.matchLabels.name = "amd-gpu-device-plugin-ds";
      template = {
        metadata.labels.name = "amd-gpu-device-plugin-ds";
        spec = {
          priorityClassName = "system-node-critical";
          nodeSelector.gpu = "amd";
          tolerations = [
            {
              key = "node.forge/mining";
              operator = "Equal";
              value = "true";
              effect = "NoSchedule";
            }
          ];
          containers = {
            _namedlist = true;
            amd-gpu-plugin = {
              image = "rocm/k8s-device-plugin:1.31.0.10";
              imagePullPolicy = "IfNotPresent";
              securityContext.privileged = true;
              env.ROCM_VISIBLE_DEVICES.value = "all";
              volumeMounts = {
                _namedlist = true;
                kubelet-root = {
                  mountPath = "/var/lib/kubelet/device-plugins";
                };
                dev-dri = {
                  mountPath = "/dev/dri";
                };
                host-dev = {
                  mountPath = "/dev";
                };
              };
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "100Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "200Mi";
                };
              };
            };
          };
          volumes = {
            _namedlist = true;
            kubelet-root.hostPath = {
              path = "/var/lib/kubelet/device-plugins";
              type = "DirectoryOrCreate";
            };
            dev-dri.hostPath = {
              path = "/dev/dri";
            };
            host-dev.hostPath = {
              path = "/dev";
            };
          };
        };
      };
      updateStrategy = {
        type = "RollingUpdate";
        rollingUpdate.maxUnavailable = 1;
      };
      revisionHistoryLimit = 2;
    };
  };

  # ── NVIDIA GPU Device Plugin ──────────────────────────────────
  # Registers NVIDIA GPUs (accelerator:nvidia-gpu nodes) with K8s
  config.kubernetes.objects.kube-system.DaemonSet.nvidia-device-plugin = {
    metadata = {
      labels =
        managed
        // {
          k8s-app = "nvidia-device-plugin";
        };
    };
    spec = {
      selector.matchLabels.k8s-app = "nvidia-device-plugin";
      template = {
        metadata.labels.k8s-app = "nvidia-device-plugin";
        spec = {
          priorityClassName = "system-node-critical";
          affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [
              {
                matchExpressions = [
                  {
                    key = "accelerator";
                    operator = "In";
                    values = ["nvidia-gpu"];
                  }
                ];
              }
            ];
          };
          tolerations = [
            {
              key = "node.forge/mining";
              operator = "Equal";
              value = "true";
              effect = "NoSchedule";
            }
            {
              key = "node.zephyr/workstation";
              operator = "Equal";
              value = "true";
              effect = "NoSchedule";
            }
          ];
          containers = {
            _namedlist = true;
            nvidia-device-plugin = {
              image = "nvcr.io/nvidia/k8s-device-plugin:v0.19.1";
              imagePullPolicy = "IfNotPresent";
              securityContext.privileged = true;
              command = ["/bin/sh" "-c" "export LD_LIBRARY_PATH=/host-driver/lib; exec /usr/bin/nvidia-device-plugin --config-file=/config/config.yaml"];
              volumeMounts = {
                _namedlist = true;
                device-plugin = {mountPath = "/var/lib/kubelet/device-plugins";};
                host-dev = {mountPath = "/dev";};
                host-driver = {
                  mountPath = "/host-driver";
                  readOnly = true;
                };
                config = {mountPath = "/config";};
                nix-store = {
                  mountPath = "/nix/store";
                  readOnly = true;
                };
              };
              resources = {};
            };
          };
          volumes = {
            _namedlist = true;
            device-plugin.hostPath = {
              path = "/var/lib/kubelet/device-plugins";
              type = "DirectoryOrCreate";
            };
            host-dev.hostPath = {path = "/dev";};
            host-driver.hostPath = {path = "/run/opengl-driver";};
            config.configMap = {name = "nvidia-device-plugin-config";};
            nix-store.hostPath = {path = "/nix/store";};
          };
        };
      };
      updateStrategy.rollingUpdate.maxUnavailable = 1;
      revisionHistoryLimit = 2;
    };
  };

  # ── NixOS Cluster MCP (SSE) ──────────────────────────────────
  config.kubernetes.objects.infra = {
    DaemonSet.nixos-cluster-mcp = {
      metadata.labels = managed // {app = "nixos-cluster-mcp";};
      spec = {
        selector.matchLabels.app = "nixos-cluster-mcp";
        template = {
          metadata = {
            labels.app = "nixos-cluster-mcp";
          };
          spec = {
            serviceAccountName = "kubernetes-mcp";
            hostNetwork = true;
            tolerations = [
              {
                key = "node-role.kubernetes.io/control-plane";
                operator = "Exists";
                effect = "NoSchedule";
              }
              {
                key = "workstation";
                operator = "Exists";
              }
              {
                key = "interactive";
                operator = "Exists";
              }
            ];
            containers = {
              _namedlist = true;
              mcp = {
                image = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
                imagePullPolicy = "IfNotPresent";
                command = ["${lib.getExe nixosClusterMcp}" "--transport" "sse" "--port" "8081"];
                env = {HOME.value = "/tmp";};
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "400m";
                    memory = "256Mi";
                  };
                };
                readinessProbe = {
                  httpGet = {
                    path = "/sse";
                    port = 8081;
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/sse";
                    port = 8081;
                  };
                  initialDelaySeconds = 15;
                  periodSeconds = 30;
                  failureThreshold = 3;
                };
                volumeMounts = {
                  _namedlist = true;
                  nix = {
                    mountPath = "/nix";
                    readOnly = true;
                  };
                  etc-nixos = {
                    mountPath = "/etc/nixos";
                    readOnly = true;
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix.hostPath = {
                path = "/nix";
                type = "Directory";
              };
              etc-nixos.hostPath = {
                path = "/etc/nixos";
                type = "Directory";
              };
            };
          };
        };
      };
      NetworkPolicy.allow-mcp = {
        metadata.labels = managed // {app = "kubernetes-mcp";};
        spec = {
          podSelector.matchLabels.app = "kubernetes-mcp";
          policyTypes = ["Ingress" "Egress"];
          ingress = [{}];
          egress = [{}];
        };
      };
      NetworkPolicy.allow-nixos-mcp = {
        metadata.labels = managed // {app = "nixos-cluster-mcp";};
        spec = {
          podSelector.matchLabels.app = "nixos-cluster-mcp";
          policyTypes = ["Ingress" "Egress"];
          ingress = [{}];
          egress = [{}];
        };
      };
    };

    # ── Local-path config: per-node storage paths ─────────────────
    # Sentry 1TB HDD at /storage should be used for bulk PVCs.
    ConfigMap.local-path-config = {
      metadata.namespace = "kube-system";
      data."config.json" = builtins.toJSON {
        nodePathMap = [
          {
            node = "DEFAULT";
            paths = ["/var/lib/rancher/k3s/storage"];
          }
          {
            node = "sentry";
            paths = ["/storage/k3s-storage"];
          }
        ];
      };
    };
  };
}
