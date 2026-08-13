{
  monitoring,
  ...
}: {
  config.kubernetes.objects = {
    # ── Rest is unchanged, starting from kube-state-metrics
    monitoring.ServiceAccount.kube-state-metrics-sa = {};
    none.ClusterRole.kube-state-metrics-role = {
      rules = [
        {
          apiGroups = [""];
          resources = [
            "configmaps"
            "secrets"
            "nodes"
            "pods"
            "limitranges"
            "replicationcontrollers"
            "resourcequotas"
            "services"
          ];
          verbs = [
            "list"
            "watch"
          ];
        }
        {
          apiGroups = ["apps"];
          resources = [
            "controllerrevisions"
            "daemonsets"
            "deployments"
            "replicasets"
            "statefulsets"
          ];
          verbs = [
            "list"
            "watch"
          ];
        }
        {
          apiGroups = ["batch"];
          resources = [
            "cronjobs"
            "jobs"
          ];
          verbs = [
            "list"
            "watch"
          ];
        }
        {
          apiGroups = ["autoscaling"];
          resources = ["horizontalpodautoscalers"];
          verbs = [
            "list"
            "watch"
          ];
        }
        {
          apiGroups = ["policy"];
          resources = ["poddisruptionbudgets"];
          verbs = [
            "list"
            "watch"
          ];
        }
        {
          apiGroups = ["storage.k8s.io"];
          resources = [
            "storageclasses"
            "volumeattachments"
          ];
          verbs = [
            "list"
            "watch"
          ];
        }
      ];
    };
    none.ClusterRoleBinding.kube-state-metrics-rolebinding = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "kube-state-metrics-role";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "kube-state-metrics-sa";
          namespace = "monitoring";
        }
      ];
    };
    monitoring.Deployment.kube-state-metrics = {
      metadata.labels = monitoring.managed // {app = "kube-state-metrics";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "kube-state-metrics";
        template = {
          metadata.labels = monitoring.managed // {app = "kube-state-metrics";};
          spec = {
            nodeSelector = {
              "kubernetes.io/hostname" = "sentry";
            };
            serviceAccountName = "kube-state-metrics-sa";
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 10001;
              runAsGroup = 10001;
              fsGroup = 10001;
              seccompProfile.type = "RuntimeDefault";
            };
            containers = {
              _namedlist = true;
              kube-state-metrics = {
                image = "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.18.0";
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--port=8080"
                  "--metric-labels-allowlist=nodes=[kubernetes.io/hostname]"
                ];
                ports = [
                  {
                    containerPort = 8080;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
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
                livenessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 8080;
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/";
                    port = 8080;
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = ["ALL"];
                };
              };
            };
          };
        };
      };
    };
    monitoring.Service.kube-state-metrics = {
      metadata.labels = monitoring.managed // {app = "kube-state-metrics";};
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 8080;
            targetPort = 8080;
            protocol = "TCP";
          }
        ];
        selector.app = "kube-state-metrics";
      };
    };

  };
}
