{
  pkgs,
  lib,
  ...
}:
let
  # nix-csi driver metadata labels
  nixCSILabels = {
    "app.kubernetes.io/name" = "nix-csi";
    "app.kubernetes.io/part-of" = "nix-csi";
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  # Host mount path for nix-csi managed store
  defaultHostMountPath = "/var/lib/nix-csi";

  # CSI driver name — must match nix.csi.store exactly
  csiDriverName = "nix.csi.store";
in
{
  config.kubernetes.objects = {

    # ── CSI Driver Registration ───────────────────────────────────
    # Tells K8s about the nix-csi driver and its capabilities.
    # Ephemeral volumes only — no PersistentVolume support needed.
    none.CSIDriver.${csiDriverName} = {
      metadata.labels = nixCSILabels;
      spec = {
        attachRequired = false;
        podInfoOnMount = true;
        volumeLifecycleModes = [ "Ephemeral" ];
        fsGroupPolicy = "File";
        requiresRepublish = false;
        storageCapacity = false;
      };
    };

    # ── Namespace ─────────────────────────────────────────────────
    none.Namespace.nix-csi = {
      metadata.labels = nixCSILabels // {
        name = "nix-csi";
      };
    };

    # ── ServiceAccount ────────────────────────────────────────────
    nix-csi.ServiceAccount.nix-csi = {
      metadata.labels = nixCSILabels;
    };

    # ── ClusterRole ───────────────────────────────────────────────
    # CSI driver needs to watch pods and report events cluster-wide.
    none.ClusterRole.nix-csi = {
      metadata.labels = nixCSILabels;
      rules = [
        {
          apiGroups = [ "" ];
          resources = [ "pods" ];
          verbs = [ "get" "list" ];
        }
        {
          apiGroups = [ "events.k8s.io" ];
          resources = [ "events" ];
          verbs = [ "get" "list" "create" "patch" ];
        }
      ];
    };

    # ── ClusterRoleBinding ────────────────────────────────────────
    none.ClusterRoleBinding.nix-csi = {
      metadata.labels = nixCSILabels;
      subjects = [{
        kind = "ServiceAccount";
        name = "nix-csi";
        namespace = "nix-csi";
      }];
      roleRef = {
        kind = "ClusterRole";
        name = "nix-csi";
        apiGroup = "rbac.authorization.k8s.io";
      };
    };

    # ── Namespaced Role ──────────────────────────────────────────
    # Additional permissions within the nix-csi namespace for
    # managing secrets (SSH keys) and configmaps (nix.conf).
    nix-csi.Role.nix-csi = {
      metadata.labels = nixCSILabels;
      rules = [
        {
          apiGroups = [ "" ];
          resources = [ "pods" ];
          verbs = [ "get" "list" "watch" ];
        }
        {
          apiGroups = [ "" ];
          resources = [ "secrets" "configmaps" ];
          verbs = [ "get" "list" "create" "patch" "delete" ];
        }
      ];
    };

    # ── RoleBinding ──────────────────────────────────────────────
    nix-csi.RoleBinding.nix-csi = {
      metadata.labels = nixCSILabels;
      subjects = [{
        kind = "ServiceAccount";
        name = "nix-csi";
      }];
      roleRef = {
        kind = "Role";
        name = "nix-csi";
        apiGroup = "rbac.authorization.k8s.io";
      };
    };

    # ── ConfigMap: Nix Configuration ──────────────────────────────
    # Shared nix.conf for all nix-csi node pods.
    nix-csi.ConfigMap.nix-node = {
      metadata.labels = nixCSILabels;
      data = {
        "nix.conf" = ''
          allowed-users = *
          trusted-users = root nix
          experimental-features = nix-command flakes read-only-local-store
          builders-use-substitutes = true
          narinfo-cache-negative-ttl = 0
          narinfo-cache-positive-ttl = 0
          warn-dirty = false
          store = daemon
          keep-outputs = true
        '';
      };
    };

    # ── ConfigMap: SSH known hosts ────────────────────────────────
    # Placeholder — populate with actual SSH host keys when configuring
    # distributed builds between cache and builder nodes.
    nix-csi.ConfigMap.ssh-config = {
      metadata.labels = nixCSILabels;
      data = {
        "ssh_config" = ''
          Host *
            StrictHostKeyChecking accept-new
            UserKnownHostsFile /dev/null
        '';
      };
    };

    # ── DaemonSet: nix-csi Node Driver ────────────────────────────
    # Runs on every node. The init container copies a pre-built nix
    # environment into the host's /var/lib/nix-csi/nix, then the main
    # container runs the CSI gRPC driver + nix daemon.
    #
    # IMPORTANT: This DaemonSet definition follows the upstream
    # nix-csi project (github:Lillecarl/nix-csi). When the upstream
    # is added as a flake input, this can be replaced with the
    # upstream's easykubenix module directly.
    nix-csi.DaemonSet.nix-node = {
      metadata.labels = nixCSILabels // {
        "app.kubernetes.io/component" = "node-driver";
      };
      spec = {
        updateStrategy = {
          type = "RollingUpdate";
          rollingUpdate.maxUnavailable = 1;
        };
        selector.matchLabels = nixCSILabels // {
          "app.kubernetes.io/component" = "node-driver";
        };
        template = {
          metadata.labels = nixCSILabels // {
            "app.kubernetes.io/component" = "node-driver";
          };
          metadata.annotations = {
            "kubectl.kubernetes.io/default-container" = "nix-node";
          };
          spec = {
            serviceAccountName = "nix-csi";
            priorityClassName = "system-node-critical";

            # Tolerate control-plane taint so CSI runs everywhere
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

            # ── Init Container ──────────────────────────────────
            # Copies the nix environment from the published container
            # image into the host's nix-csi store directory.
            initContainers = {
              _namedlist = true;
              initcopy = {
                name = "initcopy";
                image = "ghcr.io/lillecarl/nix-csi/lix:2.93";
                imagePullPolicy = "Always";
                securityContext.privileged = true;
                env = [
                  {
                    name = "amd64";
                    value = "ghcr.io/lillecarl/nix-csi/node-env:x86_64-linux";
                  }
                ];
                volumeMounts = {
                  _namedlist = true;
                  nix-store = { mountPath = "/nix-volume"; };
                  nix-config = { mountPath = "/etc/nix"; };
                  ssh-config = { mountPath = "/etc/ssh"; };
                };
                resources = {
                  requests = {
                    memory = "128Mi";
                    cpu = "100m";
                  };
                };
              };
            };

            # ── Main Containers ─────────────────────────────────
            containers = {
              _namedlist = true;

              # CSI driver — gRPC server implementing NodePublishVolume
              nix-node = {
                image = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
                command = [ "dinit" "--log-file" "/var/log/dinit.log" "--quiet" "csi" ];
                securityContext.privileged = true;
                env = [
                  { name = "CSI_ENDPOINT"; value = "unix:///csi/csi.sock"; }
                  { name = "HOME"; value = "/nix/var/nix-csi/root"; }
                  { name = "KUBE_NAMESPACE"; valueFrom.fieldRef.fieldPath = "metadata.namespace"; }
                  { name = "KUBE_NODE_NAME"; valueFrom.fieldRef.fieldPath = "spec.nodeName"; }
                  { name = "KUBE_POD_IP"; valueFrom.fieldRef.fieldPath = "status.podIP"; }
                  { name = "KUBE_POD_NAME"; valueFrom.fieldRef.fieldPath = "metadata.name"; }
                  { name = "KUBE_POD_UID"; valueFrom.fieldRef.fieldPath = "metadata.uid"; }
                  { name = "USER"; value = "root"; }
                ];
                volumeMounts = {
                  _namedlist = true;
                  csi-socket = { mountPath = "/csi"; };
                  nix-config = { mountPath = "/etc/nix"; };
                  registration = { mountPath = "/registration"; };
                  kubelet = {
                    mountPath = "/var/lib/kubelet";
                    mountPropagation = "Bidirectional";
                  };
                  nix-store = {
                    mountPath = "/nix";
                    mountPropagation = "Bidirectional";
                    subPath = "nix";
                  };
                  ssh-config = { mountPath = "/etc/ssh"; };
                };
                resources = {
                  requests = { memory = "128Mi"; cpu = "100m"; };
                  limits = { memory = "512Mi"; cpu = "500m"; };
                };
              };

              # Node driver registrar — tells kubelet about the CSI driver
              csi-node-driver-registrar = {
                image = "registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.15.0";
                args = [
                  "--v=5"
                  "--csi-address=/csi/csi.sock"
                  "--kubelet-registration-path=/var/lib/kubelet/plugins/${csiDriverName}/csi.sock"
                ];
                env = [
                  { name = "KUBE_NODE_NAME"; valueFrom.fieldRef.fieldPath = "spec.nodeName"; }
                ];
                volumeMounts = {
                  _namedlist = true;
                  csi-socket = { mountPath = "/csi"; };
                  kubelet = { mountPath = "/var/lib/kubelet"; };
                  registration = { mountPath = "/registration"; };
                };
                resources = {
                  requests = { memory = "10Mi"; cpu = "10m"; };
                };
              };

              # Liveness probe — restarts CSI driver if it becomes unresponsive
              livenessprobe = {
                image = "registry.k8s.io/sig-storage/livenessprobe:v2.17.0";
                args = [ "--csi-address=/csi/csi.sock" ];
                volumeMounts = {
                  _namedlist = true;
                  csi-socket = { mountPath = "/csi"; };
                };
                resources = {
                  requests = { memory = "10Mi"; cpu = "10m"; };
                };
              };
            };

            # ── Volumes ─────────────────────────────────────────
            volumes = {
              _namedlist = true;
              nix-config.configMap.name = "nix-node";
              registration.hostPath.path = "/var/lib/kubelet/plugins_registry";
              nix-store.hostPath = {
                path = defaultHostMountPath;
                type = "DirectoryOrCreate";
              };
              csi-socket.hostPath = {
                path = "/var/lib/kubelet/plugins/${csiDriverName}/";
                type = "DirectoryOrCreate";
              };
              kubelet.hostPath = {
                path = "/var/lib/kubelet";
                type = "Directory";
              };
              ssh-config.configMap = {
                name = "ssh-config";
                defaultMode = 292; # 0444
              };
            };
          };
        };
      };
    };

    # ── Service: Headless for builder DNS ─────────────────────────
    # Enables pods to discover each other via pod DNS for
    # distributed builds: <pod>.nix-builders.nix-csi.svc.cluster.local
    nix-csi.Service.nix-builders = {
      metadata.labels = nixCSILabels;
      spec = {
        clusterIP = "None";
        selector = nixCSILabels;
        ports = [{
          name = "ssh";
          port = 22;
        }];
      };
    };
  };
}
