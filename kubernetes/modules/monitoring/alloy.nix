{
  monitoring,
  ...
}: {
  config.kubernetes.objects = {
    # ── Alloy (DaemonSet — one per node) ───────────────────────
    monitoring.ConfigMap.alloy-config.data."config.alloy" = monitoring.alloyConfig;

    monitoring.DaemonSet.alloy = {
      metadata.labels = monitoring.managed // {app = "alloy";};
      spec = {
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "alloy";
        template = {
          metadata.labels = monitoring.managed // {app = "alloy";};
          spec = {
            serviceAccountName = "alloy-sa";
            hostNetwork = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            # Run on all nodes — Alloy is the cluster-wide log/metric collector.
            # Must tolerate workstation/interactive taints (zephyr) and control-plane.
            tolerations = [
              {
                key = "node-role.kubernetes.io/control-plane";
                effect = "NoSchedule";
              }
              {
                key = "node-role.kubernetes.io/master";
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
              {
                key = "ram-constrained";
                operator = "Exists";
              }
            ];
            securityContext = {
              runAsUser = 0;
              runAsGroup = 0;
              seccompProfile.type = "RuntimeDefault";
            };
            containers = {
              _namedlist = true;
              alloy = {
                image = monitoring.alloyImage;
                imagePullPolicy = "IfNotPresent";
                args = [
                  "run"
                  "/etc/alloy/config.alloy"
                  "--storage.path=/var/lib/alloy"
                  "--server.http.listen-addr=0.0.0.0:12345"
                ];
                env = {
                  _namedlist = true;
                  HOSTNAME.valueFrom.fieldRef.fieldPath = "spec.nodeName";
                };
                ports = [
                  {
                    containerPort = 12345;
                    name = "http";
                    protocol = "TCP";
                  }
                  {
                    containerPort = 4317;
                    name = "otlp-grpc";
                    protocol = "TCP";
                  }
                  {
                    containerPort = 4318;
                    name = "otlp-http";
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = ["ALL"];
                };
                volumeMounts = {
                  _namedlist = true;
                  config = {
                    mountPath = "/etc/alloy";
                    readOnly = true;
                  };
                  data = {
                    mountPath = "/var/lib/alloy";
                  };
                  "var-log" = {
                    mountPath = "/var/log";
                    readOnly = true;
                  };
                  "host-journal" = {
                    mountPath = "/var/log/journal";
                    readOnly = true;
                  };
                  "docker-containers" = {
                    mountPath = "/var/lib/docker/containers";
                    readOnly = true;
                  };
                  "containerd-containers" = {
                    mountPath = "/var/lib/containerd";
                    readOnly = true;
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              config.configMap.name = "alloy-config";
              data.emptyDir = {};
              "var-log" = {
                hostPath.path = "/var/log";
                hostPath.type = "DirectoryOrCreate";
                "host-journal" = {
                  hostPath.path = "/var/log/journal";
                  hostPath.type = "DirectoryOrCreate";
                };
              };
              "docker-containers" = {
                hostPath.path = "/var/lib/docker/containers";
                hostPath.type = "DirectoryOrCreate";
              };
              "containerd-containers" = {
                hostPath.path = "/var/lib/containerd";
                hostPath.type = "DirectoryOrCreate";
              };
            };
          };
        };
      };
    };

    monitoring.Service.alloy-otlp = {
      metadata.labels.app = "alloy";
      spec = {
        clusterIP = "None";
        selector.app = "alloy";
        ports = [
          {
            name = "otlp-grpc";
            port = 4317;
            targetPort = 4317;
            protocol = "TCP";
          }
          {
            name = "otlp-http";
            port = 4318;
            targetPort = 4318;
            protocol = "TCP";
          }
        ];
      };
    };
  };
}
