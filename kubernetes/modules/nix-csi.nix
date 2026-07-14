# nix-csi: CSI driver for dynamic Nix store provisioning
#
# Built from upstream github:Lillecarl/nix-csi with local images.
# Provides:
#   - nix-store StorageClass
#   - CSI driver DaemonSet (node plugin with init container)
#   - RBAC, config, namespace
#
# Images pulled from ghcr.io/lillecarl/nix-csi/ and mirrored to nexus:5000
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  # Container images - mirrored from ghcr.io/lillecarl/nix-csi/
  scratchImage = "nexus:5000/nix-csi/scratch:1.0.1";
  lixImage = "nexus:5000/nix-csi/lix:latest"; # Local build (nix-csi upstream, mirrored locally)
  csiRegistrarImage = "registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.15.0";
  livenessProbeImage = "registry.k8s.io/sig-storage/livenessprobe:v2.17.0";

  nixCsiVersion = "0.5.0";
  hostMountPath = "/var/lib/nix-csi";

  labels = {
    "app.kubernetes.io/managed-by" = "easykubenix";
    "app.kubernetes.io/part-of" = "nixos-config";
    "app.kubernetes.io/component" = "nix-csi";
  };
in {
  config.kubernetes.objects.nix-csi = {
    Namespace.nix-csi = {
      metadata.labels = labels;
    };

    StorageClass.nix-store = {
      metadata.labels = labels;
      provisioner = "nix.csi.store";
      parameters = {
        storePath = hostMountPath;
      };
      reclaimPolicy = "Retain";
      volumeBindingMode = "Immediate";
    };

    ServiceAccount.nix-csi = {
      metadata.namespace = "nix-csi";
      metadata.labels = labels;
    };

    ClusterRole.nix-csi = {
      metadata.labels = labels;
      rules = [
        {
          apiGroups = [""];
          resources = ["persistentvolumes" "nodes" "pods" "events" "configmaps"];
          verbs = ["get" "list" "watch" "create" "update" "patch"];
        }
        {
          apiGroups = [""];
          resources = ["persistentvolumeclaims"];
          verbs = ["get" "list" "watch" "update"];
        }
        {
          apiGroups = ["storage.k8s.io"];
          resources = ["volumeattachments" "storageclasses" "csidrivers" "csinodes"];
          verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
        }
        {
          apiGroups = ["apps"];
          resources = ["statefulsets" "daemonsets"];
          verbs = ["get" "list" "watch"];
        }
      ];
    };

    ClusterRoleBinding.nix-csi = {
      metadata.labels = labels;
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "nix-csi";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "nix-csi";
          namespace = "nix-csi";
        }
      ];
    };

    Service.nix-csi = {
      metadata.namespace = "nix-csi";
      metadata.labels = labels;
      spec = {
        clusterIP = "None";
        ports = [
          {
            port = 9810;
            targetPort = 9810;
            name = "health";
          }
        ];
      };
    };

    # CSI node DaemonSet
    DaemonSet.nix-csi = {
      metadata.namespace = "nix-csi";
      metadata.labels = labels // {app = "nix-csi-node";};
      spec = {
        updateStrategy.type = "RollingUpdate";
        updateStrategy.rollingUpdate.maxUnavailable = 1;
        selector.matchLabels = {app = "nix-csi";};
        template = {
          metadata.labels = labels // {app = "nix-csi";};
          spec = {
            hostNetwork = true;
            hostPID = true;
            serviceAccountName = "nix-csi";
            priorityClassName = "system-node-critical";
            tolerations = [
              {
                key = "node-role.kubernetes.io/control-plane";
                operator = "Exists";
                effect = "NoSchedule";
              }
            ];
            initContainers = [
              {
                name = "initcopy";
                image = lixImage;
                imagePullPolicy = "IfNotPresent";
                securityContext.privileged = true;
                env = [
                  {
                    name = "ARCH";
                    value = "amd64";
                  }
                ];
                volumeMounts = [
                  {
                    name = "nix-store";
                    mountPath = "/nix-volume";
                  }
                  {
                    name = "nix-config";
                    mountPath = "/etc/nix";
                  }
                ];
                resources = {
                  requests = {
                    memory = "128Mi";
                    cpu = "100m";
                  };
                };
              }
            ];
            containers = [
              {
                name = "nix-node";
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["dinit" "--log-file" "/var/log/dinit.log" "--quiet" "csi"];
                securityContext.privileged = true;
                env = [
                  {
                    name = "BUILDERS_ENABLED";
                    value = "false";
                  }
                  {
                    name = "CACHE_ENABLED";
                    value = "true";
                  }
                  {
                    name = "CSI_ENDPOINT";
                    value = "unix:///csi/csi.sock";
                  }
                  {
                    name = "HOME";
                    value = "/nix/var/nix-csi/root";
                  }
                  {
                    name = "KUBE_NAMESPACE";
                    valueFrom = {fieldRef.fieldPath = "metadata.namespace";};
                  }
                  {
                    name = "KUBE_NODE_NAME";
                    valueFrom = {fieldRef.fieldPath = "spec.nodeName";};
                  }
                  {
                    name = "KUBE_POD_IP";
                    valueFrom = {fieldRef.fieldPath = "status.podIP";};
                  }
                  {
                    name = "KUBE_POD_NAME";
                    valueFrom = {fieldRef.fieldPath = "metadata.name";};
                  }
                  {
                    name = "KUBE_POD_UID";
                    valueFrom = {fieldRef.fieldPath = "metadata.uid";};
                  }
                  {
                    name = "NIX_BUILD_TIMEOUT";
                    value = "300";
                  }
                  {
                    name = "RSYNC_CONCURRENCY";
                    value = "1";
                  }
                  {
                    name = "USER";
                    value = "root";
                  }
                ];
                volumeMounts = [
                  {
                    name = "csi-socket";
                    mountPath = "/csi";
                  }
                  {
                    name = "nix-config";
                    mountPath = "/etc/nix";
                  }
                  {
                    name = "registration";
                    mountPath = "/registration";
                  }
                  {
                    name = "kubelet";
                    mountPath = "/var/lib/kubelet";
                    mountPropagation = "Bidirectional";
                  }
                  {
                    name = "nix-store";
                    mountPath = "/nix";
                    mountPropagation = "Bidirectional";
                    subPath = "nix";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 9810;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 30;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/readyz";
                    port = 9810;
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
                resources = {
                  requests = {
                    memory = "128Mi";
                    cpu = "100m";
                  };
                  limits = {
                    memory = "512Mi";
                    cpu = "500m";
                  };
                };
              }
              {
                name = "registrar";
                image = csiRegistrarImage;
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--v=5"
                  "--csi-address=/csi/csi.sock"
                  "--kubelet-registration-path=/var/lib/kubelet/plugins/nix.csi.store/csi.sock"
                ];
                securityContext.privileged = true;
                volumeMounts = [
                  {
                    name = "csi-socket";
                    mountPath = "/csi";
                  }
                  {
                    name = "kubelet";
                    mountPath = "/var/lib/kubelet";
                  }
                  {
                    name = "registration";
                    mountPath = "/registration";
                  }
                ];
                resources = {
                  requests = {
                    memory = "10Mi";
                    cpu = "10m";
                  };
                  limits = {
                    memory = "64Mi";
                    cpu = "100m";
                  };
                };
              }
              {
                name = "liveness-probe";
                image = livenessProbeImage;
                imagePullPolicy = "IfNotPresent";
                args = ["--csi-address=/csi/csi.sock"];
                volumeMounts = [
                  {
                    name = "csi-socket";
                    mountPath = "/csi";
                  }
                ];
                resources = {
                  requests = {
                    memory = "10Mi";
                    cpu = "10m";
                  };
                  limits = {
                    memory = "32Mi";
                    cpu = "50m";
                  };
                };
              }
            ];
            volumes = [
              {
                name = "nix-config";
                configMap = {name = "nix-node";};
              }
              {
                name = "registration";
                hostPath = {
                  path = "/var/lib/kubelet/plugins_registry";
                  type = "DirectoryOrCreate";
                };
              }
              {
                name = "nix-store";
                hostPath = {
                  path = hostMountPath;
                  type = "DirectoryOrCreate";
                };
              }
              {
                name = "csi-socket";
                hostPath = {
                  path = "/var/lib/kubelet/plugins/nix.csi.store/";
                  type = "DirectoryOrCreate";
                };
              }
              {
                name = "kubelet";
                hostPath = {
                  path = "/var/lib/kubelet";
                  type = "Directory";
                };
              }
            ];
          };
        };
      };
    };

    # Nix config ConfigMap
    ConfigMap.nix-node = {
      metadata.namespace = "nix-csi";
      metadata.labels = labels;
      data."nix.conf" = ''
        max-jobs = 4
        cores = 4
        sandbox = false
        extra-sandbox-paths = /nix
        # builders = @/etc/nix/machines (disabled on zephyr)
      '';
    };
  };
}
