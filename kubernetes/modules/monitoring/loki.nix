{
  monitoring,
  ...
}: {
  config.kubernetes.objects = {
    # ── Loki ───────────────────────────────────────────────────
    monitoring.ConfigMap.loki-config.data."loki.yaml" = monitoring.lokiConfig;

    monitoring.StatefulSet.loki = {
      metadata.labels = monitoring.managed // {app = "loki";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        serviceName = "loki-headless";
        selector.matchLabels.app = "loki";
        template = {
          metadata = {
            labels.app = "loki";
          };
          spec = {
            nodeSelector = monitoring.sentrySelector;
            securityContext = monitoring.securityContext;
            serviceAccountName = "loki-sa";
            containers = {
              _namedlist = true;
              loki = {
                image = monitoring.lokiImage;
                imagePullPolicy = "IfNotPresent";
                args = [
                  "-config.file=/etc/loki/loki.yaml"
                  "-target=all"
                ];
                ports = [
                  {
                    containerPort = 3100;
                    name = "http";
                    protocol = "TCP";
                  }
                  {
                    containerPort = 9096;
                    name = "grpc";
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "250m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "1";
                    memory = "1Gi";
                  };
                };
                livenessProbe = monitoring.httpProbe 3100 "/ready";
                readinessProbe = monitoring.httpProbe 3100 "/ready";
                securityContext = monitoring.containerSecurity;
                volumeMounts = {
                  _namedlist = true;
                  config = {
                    mountPath = "/etc/loki";
                    readOnly = true;
                  };
                  data = {
                    mountPath = "/loki";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              config.configMap.name = "loki-config";
            };
          };
        };
        volumeClaimTemplates = [
          {
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              storageClassName = monitoring.storageClass;
              resources.requests.storage = "50Gi";
            };
          }
        ];
      };
    };

    monitoring.Service.loki = {
      metadata.labels = monitoring.managed // {app = "loki";};
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 3100;
            targetPort = 3100;
            protocol = "TCP";
          }
          {
            name = "grpc";
            port = 9096;
            targetPort = 9096;
            protocol = "TCP";
          }
        ];
        selector.app = "loki";
      };
    };
    monitoring.Service.loki-headless = {
      metadata.labels = monitoring.managed // {app = "loki";};
      spec = {
        type = "ClusterIP";
        clusterIP = "None";
        ports = [
          {
            name = "http";
            port = 3100;
            targetPort = 3100;
            protocol = "TCP";
          }
        ];
        selector.app = "loki";
      };
    };

    # ── PodDisruptionBudget ──
    monitoring.PodDisruptionBudget.loki-pdb = {
      spec.maxUnavailable = 1;
      spec.selector.matchLabels.app = "loki";
    };
  };
}
