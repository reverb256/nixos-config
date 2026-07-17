<<<<<<< HEAD
{
  config,
  lib,
  pkgs,
  ...
}: let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
  labels = {
    app = "falco";
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects.monitoring = {
    # NOTE: Namespace.monitoring is defined in monitoring.nix. We only add
    # resources here; do NOT redefine the namespace to avoid label conflicts.

    # ── ServiceAccount / RBAC ─────────────────────────────────────
    ServiceAccount.falco = {
      metadata.labels = labels;
    };

    ClusterRole.falco = {
      metadata.labels = labels;
      rules = [
        {
          apiGroups = [""];
          resources = ["pods" "nodes" "namespaces" "services" "configmaps"];
          verbs = ["get" "list" "watch"];
        }
        {
          apiGroups = ["apps"];
          resources = ["deployments" "replicasets" "daemonsets" "statefulsets"];
          verbs = ["get" "list" "watch"];
        }
      ];
    };

    ClusterRoleBinding.falco = {
      metadata.labels = labels;
      subjects = [
        {
          kind = "ServiceAccount";
          name = "falco";
          namespace = "monitoring";
        }
      ];
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "falco";
      };
    };

    # ── ConfigMap: minimal Falco rules ─────────────────────────────
    ConfigMap.falco-config = {
      metadata.labels = labels;
      data = {
        "falco.yaml" = builtins.toJSON {
          rules_file = ["/etc/falco/falco_rules.yaml" "/etc/falco/custom/falco_rules.local.yaml" "/etc/falco/rules.d"];
          json_output = true;
          json_include_output_property = true;
          http_output = {
            enabled = false;
          };
          file_output = {
            enabled = true;
            filename = "/var/log/falco/events.log";
          };
          stdout_output = {
            enabled = true;
          };
          syslog_output = {
            enabled = false;
          };
          grpc = {
            enabled = false;
          };
          grpc_output = {
            enabled = false;
          };
        };
        "falco_rules.local.yaml" = ''
          - rule: Terminal shell in container
            desc: A shell was spawned in a container
            condition: spawned_process and container and shell_procs and not proc.name in (bash, sh)
            output: >-
              Terminal shell in container
              (user=%user.name command=%proc.cmdline container=%container.name)
            priority: NOTICE

          - rule: Privileged container started
            desc: A privileged container was started
            condition: container_started and container.privileged=true
            output: >-
              Privileged container started
              (user=%user.name command=%proc.cmdline image=%container.image)
            priority: WARNING
        '';
        # Empty placeholder so the ConfigMap mount does not hide the image's
        # built-in /etc/falco/falco_rules.yaml. We mount the ConfigMap to
        # /etc/falco/custom and point rules_file there; the default rules
        # remain available at /etc/falco/falco_rules.yaml from the image.
        ".placeholder" = "";
      };
    };

    # ── DaemonSet: Falco ───────────────────────────────────────────
    DaemonSet.falco = {
      metadata.labels = labels;
      spec = {
        selector.matchLabels.app = "falco";
        updateStrategy.type = "RollingUpdate";
        template = {
          metadata.labels = labels;
          spec = {
            serviceAccountName = "falco";
            tolerations = [
              {
                key = "node-role.kubernetes.io/control-plane";
                operator = "Exists";
                effect = "NoSchedule";
              }
              {
                key = "node.forge/mining";
                operator = "Exists";
                effect = "NoSchedule";
              }
              {
                key = "node.zephyr/workstation";
                operator = "Exists";
                effect = "NoSchedule";
              }
            ];
            containers = {
              _namedlist = true;
              falco = {
                image = "falcosecurity/falco:0.39.0";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  privileged = true;
                };
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "1Gi";
                  };
                };
                livenessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 8765;
                  };
                  initialDelaySeconds = 60;
                  periodSeconds = 30;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 8765;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                volumeMounts = {
                  _namedlist = true;
                  proc = {
                    mountPath = "/host/proc";
                    readOnly = true;
                  };
                  sys = {
                    mountPath = "/host/sys";
                    readOnly = true;
                  };
                  dev = {
                    mountPath = "/host/dev";
                    readOnly = true;
                  };
                  etc = {
                    mountPath = "/host/etc";
                    readOnly = true;
                  };
                  boot = {
                    mountPath = "/host/boot";
                    readOnly = true;
                  };
                  usr = {
                    mountPath = "/host/usr";
                    readOnly = true;
                  };
                  containerd = {
                    mountPath = "/host/run/containerd";
                    readOnly = true;
                  };
                  k3s-containerd = {
                    mountPath = "/host/run/k3s/containerd";
                    readOnly = true;
                  };
                  falco-config = {
                    mountPath = "/etc/falco/custom";
                    readOnly = true;
                  };
                  falco-logs = {
                    mountPath = "/var/log/falco";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              proc.hostPath = {
                path = "/proc";
                type = "Directory";
              };
              sys.hostPath = {
                path = "/sys";
                type = "Directory";
              };
              dev.hostPath = {
                path = "/dev";
                type = "Directory";
              };
              etc.hostPath = {
                path = "/etc";
                type = "Directory";
              };
              boot.hostPath = {
                path = "/boot";
                type = "Directory";
              };
              usr.hostPath = {
                path = "/usr";
                type = "Directory";
              };
              containerd.hostPath = {
                path = "/run/containerd";
                type = "DirectoryOrCreate";
              };
              k3s-containerd.hostPath = {
                path = "/run/k3s/containerd";
                type = "DirectoryOrCreate";
              };
              falco-config.configMap = {
                name = "falco-config";
              };
              falco-logs.hostPath = {
                path = "/var/log/falco";
                type = "DirectoryOrCreate";
              };
            };
          };
        };
      };
    };
  };
}
||||||| f46c16eb
=======
{
  config,
  lib,
  pkgs,
  ...
}: let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
  labels = {
    app = "falco";
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects.monitoring = {
    # NOTE: Namespace.monitoring is defined in monitoring.nix. We only add
    # resources here; do NOT redefine the namespace to avoid label conflicts.

    # ── ServiceAccount / RBAC ─────────────────────────────────────
    ServiceAccount.falco = {
      metadata.labels = labels;
    };

    ClusterRole.falco = {
      metadata.labels = labels;
      rules = [
        {
          apiGroups = [""];
          resources = ["pods" "nodes" "namespaces" "services" "configmaps"];
          verbs = ["get" "list" "watch"];
        }
        {
          apiGroups = ["apps"];
          resources = ["deployments" "replicasets" "daemonsets" "statefulsets"];
          verbs = ["get" "list" "watch"];
        }
      ];
    };

    ClusterRoleBinding.falco = {
      metadata.labels = labels;
      subjects = [
        {
          kind = "ServiceAccount";
          name = "falco";
          namespace = "monitoring";
        }
      ];
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "falco";
      };
    };

    # ── ConfigMap: minimal Falco rules ─────────────────────────────
    ConfigMap.falco-config = {
      metadata.labels = labels;
      data = {
        "falco.yaml" = builtins.toJSON {
          rules_file = ["/etc/falco/falco_rules.yaml" "/etc/falco/custom/falco_rules.local.yaml" "/etc/falco/rules.d"];
          json_output = true;
          json_include_output_property = true;
          http_output = {
            enabled = false;
          };
          file_output = {
            enabled = true;
            filename = "/var/log/falco/events.log";
          };
          stdout_output = {
            enabled = true;
          };
          syslog_output = {
            enabled = false;
          };
          grpc = {
            enabled = false;
          };
          grpc_output = {
            enabled = false;
          };
        };
        "falco_rules.local.yaml" = ''
          - rule: Terminal shell in container
            desc: A shell was spawned in a container
            condition: spawned_process and container and shell_procs and not proc.name in (bash, sh)
            output: >
              Terminal shell in container
              (user=%user.name command=%proc.cmdline container=%container.name)
            priority: NOTICE

          - rule: Privileged container started
            desc: A privileged container was started
            condition: container_started and container.privileged=true
            output: >
              Privileged container started
              (user=%user.name command=%proc.cmdline image=%container.image)
            priority: WARNING
        '';
        # Empty placeholder so the ConfigMap mount does not hide the image's
        # built-in /etc/falco/falco_rules.yaml. We mount the ConfigMap to
        # /etc/falco/custom and point rules_file there; the default rules
        # remain available at /etc/falco/falco_rules.yaml from the image.
        ".placeholder" = "";
      };
    };

    # ── DaemonSet: Falco ───────────────────────────────────────────
    DaemonSet.falco = {
      metadata.labels = labels;
      spec = {
        selector.matchLabels.app = "falco";
        updateStrategy.type = "RollingUpdate";
        template = {
          metadata.labels = labels;
          spec = {
            serviceAccountName = "falco";
            tolerations = [
              {
                key = "node-role.kubernetes.io/control-plane";
                operator = "Exists";
                effect = "NoSchedule";
              }
              {
                key = "node.forge/mining";
                operator = "Exists";
                effect = "NoSchedule";
              }
              {
                key = "node.zephyr/workstation";
                operator = "Exists";
                effect = "NoSchedule";
              }
            ];
            containers = {
              _namedlist = true;
              falco = {
                image = "falcosecurity/falco:0.39.0";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  privileged = true;
                };
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "1Gi";
                  };
                };
                livenessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 8765;
                  };
                  initialDelaySeconds = 60;
                  periodSeconds = 30;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 8765;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                volumeMounts = {
                  _namedlist = true;
                  proc = {
                    mountPath = "/host/proc";
                    readOnly = true;
                  };
                  sys = {
                    mountPath = "/host/sys";
                    readOnly = true;
                  };
                  dev = {
                    mountPath = "/host/dev";
                    readOnly = true;
                  };
                  etc = {
                    mountPath = "/host/etc";
                    readOnly = true;
                  };
                  boot = {
                    mountPath = "/host/boot";
                    readOnly = true;
                  };
                  usr = {
                    mountPath = "/host/usr";
                    readOnly = true;
                  };
                  containerd = {
                    mountPath = "/host/run/containerd";
                    readOnly = true;
                  };
                  k3s-containerd = {
                    mountPath = "/host/run/k3s/containerd";
                    readOnly = true;
                  };
                  falco-config = {
                    mountPath = "/etc/falco/custom";
                    readOnly = true;
                  };
                  falco-logs = {
                    mountPath = "/var/log/falco";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              proc.hostPath = {
                path = "/proc";
                type = "Directory";
              };
              sys.hostPath = {
                path = "/sys";
                type = "Directory";
              };
              dev.hostPath = {
                path = "/dev";
                type = "Directory";
              };
              etc.hostPath = {
                path = "/etc";
                type = "Directory";
              };
              boot.hostPath = {
                path = "/boot";
                type = "Directory";
              };
              usr.hostPath = {
                path = "/usr";
                type = "Directory";
              };
              containerd.hostPath = {
                path = "/run/containerd";
                type = "DirectoryOrCreate";
              };
              k3s-containerd.hostPath = {
                path = "/run/k3s/containerd";
                type = "DirectoryOrCreate";
              };
              falco-config.configMap = {
                name = "falco-config";
              };
              falco-logs.hostPath = {
                path = "/var/log/falco";
                type = "DirectoryOrCreate";
              };
            };
          };
        };
      };
    };
  };
}
>>>>>>> central/issue-291-audit-remediation
