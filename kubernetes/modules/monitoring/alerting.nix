{
  monitoring,
  ...
}: {
  config.kubernetes.objects = {
    # ── AlertManager ───────────────────────────────────────
    monitoring.ConfigMap.alertmanager-config = {
      metadata.labels = monitoring.managed // {app = "alertmanager";};
      data."alertmanager.yml" = ''
        global:
          resolve_timeout: 5m
        route:
          group_by: ['alertname', 'severity']
          group_wait: 10s
          group_interval: 10s
          receiver: 'log-only'
          routes:
            - match:
                severity: critical
              receiver: 'log-only'
            - match:
                severity: warning
              receiver: 'log-only'
        receivers:
          - name: 'log-only'
            # Alerts are logged by AlertManager itself → Alloy → Loki.
            # Add real notification channels (Slack/Discord) here when ready.
        inhibit_rules:
          - source_match:
              severity: 'critical'
            target_match:
              severity: 'warning'
            equal: ['alertname', 'instance']
      '';
    };

    monitoring.ServiceAccount.alertmanager-sa = {};

    monitoring.Deployment.alertmanager = {
      metadata.labels = monitoring.managed // {app = "alertmanager";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "alertmanager";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 0;
            maxUnavailable = 1;
          };
        };
        template = {
          metadata = {
            labels.app = "alertmanager";
          };
          spec = {
            nodeSelector = monitoring.sentrySelector;
            serviceAccountName = "alertmanager-sa";
            containers = {
              _namedlist = true;
              alertmanager = {
                image = "docker.io/prom/alertmanager:v0.32.1";
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--config.file=/etc/alertmanager/alertmanager.yml"
                  "--storage.path=/alertmanager"
                  "--web.listen-address=:9093"
                  "--cluster.listen-address=:9094"
                ];
                ports = [
                  {
                    containerPort = 9093;
                    name = "http";
                    protocol = "TCP";
                  }
                  {
                    containerPort = 9094;
                    name = "cluster";
                    protocol = "TCP";
                  }
                ];
                volumeMounts = {
                  _namedlist = true;
                  config = {
                    mountPath = "/etc/alertmanager";
                    readOnly = true;
                  };
                  data = {
                    mountPath = "/alertmanager";
                  };
                };
                securityContext = {
                  runAsNonRoot = true;
                  runAsUser = 10002;
                  runAsGroup = 10002;
                  fsGroup = 10002;
                  seccompProfile.type = "RuntimeDefault";
                };
              };
            };
            volumes = {
              _namedlist = true;
              config = {
                name = "alertmanager-config";
                configMap.name = "alertmanager-config";
              };
            };
          };
        };
      };
    };

    monitoring.Service.alertmanager = {
      metadata.labels = monitoring.managed // {app = "alertmanager";};
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 9093;
            targetPort = 9093;
            protocol = "TCP";
          }
        ];
        selector.app = "alertmanager";
      };
    };

    # AlertManager logs alerts to stdout → Alloy → Loki.
    # No separate webhook deployment needed until real notification (Slack/Discord) is configured.

    # ── Alert Webhook (placeholder) ─────────────────────────────────
    # Receives alertmanager webhooks. Currently a placeholder (sleep infinity)
    # on nexus. Will be replaced with real notification handler.
    monitoring.Deployment.alert-webhook = {
      metadata.labels = monitoring.managed // {app = "alert-webhook";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "alert-webhook";
        strategy.type = "Recreate";
        template = {
          metadata.labels.app = "alert-webhook";
          spec = {
            nodeName = "nexus";
            automountServiceAccountToken = false;
            containers = [
              {
                name = "webhook";
                image = "docker.io/library/bash:5.2";
                command = ["sleep" "infinity"];
                ports = [
                  {
                    name = "http";
                    containerPort = 9093;
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "16Mi";
                  };
                  limits = {
                    cpu = "100m";
                    memory = "64Mi";
                  };
                };
              }
            ];
          };
        };
      };
    };

    monitoring.Service.alert-webhook = {
      metadata.labels = monitoring.managed // {app = "alert-webhook";};
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 9093;
            targetPort = 9093;
            protocol = "TCP";
          }
        ];
        selector.app = "alert-webhook";
      };
    };
  };
}
