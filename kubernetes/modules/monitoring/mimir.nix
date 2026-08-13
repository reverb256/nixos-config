{
  monitoring,
  ...
}: {
  config.kubernetes.objects = {
    # ── Mimir ──────────────────────────────────────────────────
    monitoring.ConfigMap.mimir-config.data."mimir.yaml" = monitoring.mimirConfig;

    monitoring.StatefulSet.mimir = {
      metadata.labels = monitoring.managed // {app = "mimir";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        serviceName = "mimir-headless";
        selector.matchLabels.app = "mimir";
        template = {
          metadata = {
            labels.app = "mimir";
          };
          spec = {
            nodeSelector = monitoring.sentrySelector;
            securityContext = monitoring.securityContext;
            serviceAccountName = "mimir-sa";
            containers = {
              _namedlist = true;
              mimir = {
                image = monitoring.mimirImage;
                imagePullPolicy = "IfNotPresent";
                args = [
                  "-config.file=/etc/mimir/mimir.yaml"
                  "-target=all"
                ];
                ports = [
                  {
                    containerPort = 9009;
                    name = "http";
                    protocol = "TCP";
                  }
                  {
                    containerPort = 9095;
                    name = "grpc";
                    protocol = "TCP";
                  }
                  {
                    containerPort = 7946;
                    name = "memberlist";
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "500m";
                    memory = "1Gi";
                  };
                  limits = {
                    cpu = "2";
                    memory = "2Gi";
                  };
                };
                livenessProbe = monitoring.httpProbe 9009 "/ready";
                readinessProbe = monitoring.httpProbe 9009 "/ready";
                securityContext = monitoring.containerSecurity;
                volumeMounts = {
                  _namedlist = true;
                  config = {
                    mountPath = "/etc/mimir";
                    readOnly = true;
                  };
                  data = {
                    mountPath = "/mimir";
                  };
                  activity = {
                    mountPath = "/mimir/activity";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              config.configMap.name = "mimir-config";
              activity.emptyDir = {};
            };
          };
        };
        volumeClaimTemplates = [
          {
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              storageClassName = monitoring.storageClass;
              resources.requests.storage = "100Gi";
            };
          }
        ];
      };
    };

    monitoring.Service.mimir = {
      metadata.labels = monitoring.managed // {app = "mimir";};
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 9009;
            targetPort = 9009;
            protocol = "TCP";
          }
          {
            name = "grpc";
            port = 9095;
            targetPort = 9095;
            protocol = "TCP";
          }
        ];
        selector.app = "mimir";
      };
    };
    monitoring.Service.mimir-headless = {
      metadata.labels = monitoring.managed // {app = "mimir";};
      spec = {
        type = "ClusterIP";
        clusterIP = "None";
        ports = [
          {
            name = "http";
            port = 9009;
            targetPort = 9009;
            protocol = "TCP";
          }
        ];
        selector.app = "mimir";
      };
    };

    # ── PodDisruptionBudget ──
    monitoring.PodDisruptionBudget.mimir-pdb = {
      spec.maxUnavailable = 1;
      spec.selector.matchLabels.app = "mimir";
    };
  };
}
