{
  monitoring,
  ...
}: {
  config.kubernetes.objects = {
    # ── Prometheus (scrapes targets, remote_writes to Mimir) ───
    monitoring.ConfigMap.prometheus-config.data."prometheus.yml" = monitoring.prometheusConfig;

    monitoring.Deployment.prometheus = {
      metadata.labels = monitoring.managed // {app = "prometheus";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "prometheus";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 0;
            maxUnavailable = 1;
          };
        };
        template = {
          metadata = {
            labels.app = "prometheus";
          };
          spec = {
            nodeSelector = monitoring.sentrySelector;
            securityContext = {
              runAsUser = 10001;
              runAsGroup = 10001;
              fsGroup = 10001;
              runAsNonRoot = true;
              seccompProfile.type = "RuntimeDefault";
            };
            serviceAccountName = "prometheus-sa";
            containers = {
              _namedlist = true;
              prometheus = {
                image = monitoring.prometheusImage;
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--config.file=/etc/prometheus/prometheus.yml"
                  "--storage.tsdb.path=/prometheus"
                  "--storage.tsdb.retention.time=2h"
                  "--storage.tsdb.retention.size=1GB"
                  "--web.enable-remote-write-receiver"
                  "--web.listen-address=0.0.0.0:9090"
                ];
                ports = [
                  {
                    containerPort = 9090;
                    name = "http";
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
                livenessProbe = monitoring.httpProbe 9090 "/-/healthy";
                readinessProbe = monitoring.httpProbe 9090 "/-/ready";
                securityContext = monitoring.containerSecurity;
                volumeMounts = {
                  _namedlist = true;
                  config = {
                    mountPath = "/etc/prometheus";
                    readOnly = true;
                  };
                  data = {
                    mountPath = "/prometheus";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              config.configMap.name = "prometheus-config";
              data.emptyDir = {}; # Short retention — Mimir handles long-term
            };
          };
        };
      };
    };

    monitoring.Service.prometheus = {
      metadata.labels = monitoring.managed // {app = "prometheus";};
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 9090;
            targetPort = 9090;
            protocol = "TCP";
          }
        ];
        selector.app = "prometheus";
      };
    };

  };
}
