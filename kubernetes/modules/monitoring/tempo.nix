{
  monitoring,
  ...
}: {
  config.kubernetes.objects = {
    # ── Tempo ──────────────────────────────────────────────────
    monitoring.ConfigMap.tempo-config.data."tempo.yaml" = monitoring.tempoConfig;

    monitoring.StatefulSet.tempo = {
      metadata.labels = monitoring.managed // {app = "tempo";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        serviceName = "tempo-headless";
        selector.matchLabels.app = "tempo";
        template = {
          metadata = {
            labels.app = "tempo";
          };
          spec = {
            nodeSelector = monitoring.sentrySelector;
            securityContext = monitoring.securityContext;
            serviceAccountName = "tempo-sa";
            containers = {
              _namedlist = true;
              tempo = {
                image = monitoring.tempoImage;
                imagePullPolicy = "IfNotPresent";
                args = ["-config.file=/etc/tempo/tempo.yaml"];
                ports = [
                  {
                    containerPort = 3200;
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
                    cpu = "250m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "1";
                    memory = "1Gi";
                  };
                };
                livenessProbe = monitoring.httpProbe 3200 "/ready";
                readinessProbe = monitoring.httpProbe 3200 "/ready";
                securityContext = monitoring.containerSecurity;
                volumeMounts = {
                  _namedlist = true;
                  config = {
                    mountPath = "/etc/tempo";
                    readOnly = true;
                  };
                  data = {
                    mountPath = "/data";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              config.configMap.name = "tempo-config";
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

    monitoring.Service.tempo = {
      metadata.labels = monitoring.managed // {app = "tempo";};
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 3200;
            targetPort = 3200;
            protocol = "TCP";
          }
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
        selector.app = "tempo";
      };
    };
    monitoring.Service.tempo-headless = {
      metadata.labels = monitoring.managed // {app = "tempo";};
      spec = {
        type = "ClusterIP";
        clusterIP = "None";
        ports = [
          {
            name = "http";
            port = 3200;
            targetPort = 3200;
            protocol = "TCP";
          }
        ];
        selector.app = "tempo";
      };
    };

  };
}
