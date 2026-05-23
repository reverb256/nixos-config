# nix-csi: CSI driver + StorageClass for dynamic Nix store provisioning
#
# Generates Kubernetes manifests directly for the nix-csi CSI driver
# (github:Lillecarl/nix-csi). The upstream kubenix module has internal
# config recursion issues when imported via easykubenix, so we generate
# resources directly here.
#
# Provides:
#   - nix-store StorageClass (points to nix-csi CSI driver)
#   - CSI driver DaemonSet + StatefulSet (cache, builder)
#   - RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)
#   - nix-csi namespace
#
# See upstream: https://github.com/Lillecarl/nix-csi
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  # nix-csi scratch image for init containers
  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
  nixCsiVersion = "0.4.3";

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
      provisioner = "nix-csi.csi.k8s.io";
      parameters = {
        # Store Nix artifacts at this host path
        storePath = "/var/lib/nix-csi/store";
      };
      mountOptions = ["vers=4.1" "hard" "noatime"];
      reclaimPolicy = "Delete";
      volumeBindingMode = "Immediate";
    };

    ServiceAccount.nix-csi-controller = {
      metadata = {
        namespace = "nix-csi";
        labels = labels;
      };
    };

    ClusterRole.nix-csi-controller = {
      metadata.labels = labels;
      rules = [
        {
          apiGroups = [""];
          resources = ["nodes" "persistentvolumes" "events" "configmaps"];
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

    ClusterRoleBinding.nix-csi-controller = {
      metadata.labels = labels;
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "nix-csi-controller";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "nix-csi-controller";
          namespace = "nix-csi";
        }
      ];
    };

    # CSI controller StatefulSet (manages volume lifecycle)
    StatefulSet.nix-csi-controller = {
      metadata = {
        namespace = "nix-csi";
        labels = labels // {
          app = "nix-csi-controller";
        };
      };
      spec = {
        replicas = 1;
        serviceName = "nix-csi";
        selector.matchLabels = {
          app = "nix-csi-controller";
        };
        template = {
          metadata.labels = labels // {
            app = "nix-csi-controller";
          };
          spec = {
            serviceAccountName = "nix-csi-controller";
            containers = {
              _namedlist = true;
              nix-csi = {
                image = "quay.io/lillecarl/nix-csi:${nixCsiVersion}";
                imagePullPolicy = "IfNotPresent";
                args = ["controller"];
                env = [
                  {
                    name = "POD_NAMESPACE";
                    valueFrom = {
                      fieldRef.fieldPath = "metadata.namespace";
                    };
                  }
                  {
                    name = "NIX_CSI_NODE_NAME";
                    valueFrom = {
                      fieldRef.fieldPath = "spec.nodeName";
                    };
                  }
                ];
                ports = [
                  {
                    containerPort = 9810;
                    name = "health";
                    protocol = "TCP";
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
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
              };
            };
          };
        };
      };
    };

    # CSI node DaemonSet (runs on every node, handles mount operations)
    DaemonSet.nix-csi-node = {
      metadata = {
        namespace = "nix-csi";
        labels = labels // {
          app = "nix-csi-node";
        };
      };
      spec = {
        selector.matchLabels = {
          app = "nix-csi-node";
        };
        template = {
          metadata.labels = labels // {
            app = "nix-csi-node";
          };
          spec = {
            hostNetwork = true;
            hostPID = true;
            serviceAccountName = "nix-csi-controller";
            tolerations = [
              {
                operator = "Exists";
                effect = "NoSchedule";
              }
              {
                operator = "Exists";
                effect = "NoExecute";
              }
            ];
            containers = {
              _namedlist = true;
              nix-csi = {
                image = "quay.io/lillecarl/nix-csi:${nixCsiVersion}";
                imagePullPolicy = "IfNotPresent";
                args = ["node"];
                securityContext = {
                  privileged = true;
                  capabilities.add = ["SYS_ADMIN"];
                };
                env = [
                  {
                    name = "NIX_CSI_NODE_NAME";
                    valueFrom = {
                      fieldRef.fieldPath = "spec.nodeName";
                    };
                  }
                ];
                ports = [
                  {
                    containerPort = 9810;
                    name = "health";
                    protocol = "TCP";
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
                volumeMounts = {
                  _namedlist = true;
                  plugin-dir = {
                    mountPath = "/var/lib/kubelet/plugins/nix-csi.csi.k8s.io";
                    mountPropagation = "Bidirectional";
                  };
                  pods-dir = {
                    mountPath = "/var/lib/kubelet/pods";
                    mountPropagation = "Bidirectional";
                  };
                  registration-dir = {
                    mountPath = "/var/lib/kubelet/plugins_registry";
                    mountPropagation = "Bidirectional";
                  };
                  host-nix = {
                    mountPath = "/nix/host";
                    mountPropagation = "Bidirectional";
                  };
                  host-dev = {
                    mountPath = "/dev";
                    mountPropagation = "Bidirectional";
                  };
                };
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
              };
              registrar = {
                image = "registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.10.0";
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--v=5"
                  "--csi-address=/csi/csi.sock"
                  "--kubelet-registration-path=/var/lib/kubelet/plugins/nix-csi.csi.k8s.io/csi.sock"
                ];
                securityContext = {
                  privileged = true;
                };
                volumeMounts = {
                  _namedlist = true;
                  plugin-dir = {
                    mountPath = "/csi";
                  };
                  registration-dir = {
                    mountPath = "/registration";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              plugin-dir.hostPath = {
                path = "/var/lib/kubelet/plugins/nix-csi.csi.k8s.io";
                type = "DirectoryOrCreate";
              };
              pods-dir.hostPath = {
                path = "/var/lib/kubelet/pods";
                type = "Directory";
              };
              registration-dir.hostPath = {
                path = "/var/lib/kubelet/plugins_registry";
                type = "DirectoryOrCreate";
              };
              host-nix.hostPath = {
                path = "/nix";
                type = "Directory";
              };
              host-dev.hostPath = {
                path = "/dev";
                type = "Directory";
              };
            };
          };
        };
      };
    };

    # CSI driver registration
    CSIDriver.nix-csi.csi.k8s.io = {
      metadata.labels = labels;
      spec = {
        attachRequired = false;
        podInfoOnMount = true;
        volumeLifecycleModes = ["Persistent" "Ephemeral"];
      };
    };

    # Service for nix-csi controller (headless for StatefulSet)
    Service.nix-csi = {
      metadata = {
        namespace = "nix-csi";
        labels = labels;
      };
      spec = {
        clusterIP = "None";
        ports = [
          {
            name = "health";
            port = 9810;
            protocol = "TCP";
          }
        ];
        selector = {
          app = "nix-csi-controller";
        };
      };
    };
  };
}
