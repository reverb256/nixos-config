{...}: let
  version = "v1.20.2";
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
    "app.kubernetes.io/part-of" = "cert-manager";
  };
in {
  config.kubernetes.objects = {
    # ── Namespace ─────────────────────────────────────────────────
    none.Namespace.cert-manager = {
      metadata.labels =
        managed
        // {
          name = "cert-manager";
          "pod-security.kubernetes.io/enforce" = "baseline";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        };
    };

    # ── ServiceAccounts ──────────────────────────────────────────
    cert-manager.ServiceAccount.cert-manager = {
      metadata.labels =
        managed
        // {
          app = "cert-manager";
          "app.kubernetes.io/component" = "controller";
        };
    };
    cert-manager.ServiceAccount.cert-manager-cainjector = {
      metadata.labels =
        managed
        // {
          app = "cert-manager-cainjector";
          "app.kubernetes.io/component" = "cainjector";
        };
    };
    cert-manager.ServiceAccount.cert-manager-webhook = {
      metadata.labels =
        managed
        // {
          app = "cert-manager-webhook";
          "app.kubernetes.io/component" = "webhook";
        };
    };

    # ── Services ─────────────────────────────────────────────────
    cert-manager.Service.cert-manager = {
      metadata.labels =
        managed
        // {
          app = "cert-manager";
          "app.kubernetes.io/component" = "controller";
          "app.kubernetes.io/instance" = "cert-manager";
        };
      spec = {
        type = "ClusterIP";
        selector = {
          "app.kubernetes.io/component" = "controller";
          "app.kubernetes.io/instance" = "cert-manager";
          "app.kubernetes.io/name" = "cert-manager";
        };
        ports.tcp-prometheus-servicemonitor = {
          port = 9402;
          targetPort = "http-metrics";
          protocol = "TCP";
        };
      };
    };
    cert-manager.Service.cert-manager-cainjector = {
      metadata.labels =
        managed
        // {
          app = "cert-manager-cainjector";
          "app.kubernetes.io/component" = "cainjector";
          "app.kubernetes.io/instance" = "cert-manager";
        };
      spec = {
        type = "ClusterIP";
        selector = {
          "app.kubernetes.io/component" = "cainjector";
          "app.kubernetes.io/instance" = "cert-manager";
          "app.kubernetes.io/name" = "cainjector";
        };
        ports.http-metrics = {
          port = 9402;
          targetPort = 9402;
          protocol = "TCP";
        };
      };
    };
    cert-manager.Service.cert-manager-webhook = {
      metadata.labels =
        managed
        // {
          app = "cert-manager-webhook";
          "app.kubernetes.io/component" = "webhook";
          "app.kubernetes.io/instance" = "cert-manager";
        };
      spec = {
        type = "ClusterIP";
        selector = {
          "app.kubernetes.io/component" = "webhook";
          "app.kubernetes.io/instance" = "cert-manager";
          "app.kubernetes.io/name" = "webhook";
        };
        ports = [
          {
            name = "https";
            port = 443;
            targetPort = "https";
            protocol = "TCP";
          }
          {
            name = "metrics";
            port = 9402;
            targetPort = "http-metrics";
            protocol = "TCP";
          }
        ];
      };
    };

    # ── Deployments ──────────────────────────────────────────────
    cert-manager.Deployment.cert-manager = {
      metadata.labels =
        managed
        // {
          app = "cert-manager";
          "app.kubernetes.io/component" = "controller";
          "app.kubernetes.io/instance" = "cert-manager";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels = {
          "app.kubernetes.io/component" = "controller";
          "app.kubernetes.io/instance" = "cert-manager";
          "app.kubernetes.io/name" = "cert-manager";
        };
        strategy.type = "Recreate";
        template = {
          metadata.labels = {
            "app.kubernetes.io/component" = "controller";
            "app.kubernetes.io/instance" = "cert-manager";
            "app.kubernetes.io/name" = "cert-manager";
          };
          spec = {
            serviceAccountName = "cert-manager";
            nodeSelector."kubernetes.io/os" = "linux";
            containers = [
              {
                name = "cert-manager";
                image = "quay.io/jetstack/cert-manager-controller:${version}";
                args = [
                  "--v=2"
                  "--cluster-resource-namespace=$(POD_NAMESPACE)"
                  "--leader-election-namespace=kube-system"
                  "--acme-http01-solver-image=quay.io/jetstack/cert-manager-acmesolver:${version}"
                  "--max-concurrent-challenges=60"
                ];
                env.POD_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                ports = [
                  {
                    name = "http-metrics";
                    containerPort = 9402;
                    protocol = "TCP";
                  }
                  {
                    name = "http-healthz";
                    containerPort = 9403;
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
              }
            ];
          };
        };
      };
    };

    cert-manager.Deployment.cert-manager-cainjector = {
      metadata.labels =
        managed
        // {
          app = "cert-manager-cainjector";
          "app.kubernetes.io/component" = "cainjector";
          "app.kubernetes.io/instance" = "cert-manager";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels = {
          "app.kubernetes.io/component" = "cainjector";
          "app.kubernetes.io/instance" = "cert-manager";
          "app.kubernetes.io/name" = "cainjector";
        };
        strategy.type = "Recreate";
        template = {
          metadata.labels = {
            "app.kubernetes.io/component" = "cainjector";
            "app.kubernetes.io/instance" = "cert-manager";
            "app.kubernetes.io/name" = "cainjector";
          };
          spec = {
            serviceAccountName = "cert-manager-cainjector";
            nodeSelector."kubernetes.io/os" = "linux";
            containers = [
              {
                name = "cert-manager-cainjector";
                image = "quay.io/jetstack/cert-manager-cainjector:${version}";
                args = [
                  "--v=2"
                  "--leader-election-namespace=kube-system"
                ];
                env.POD_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                ports = [
                  {
                    name = "http-metrics";
                    containerPort = 9402;
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
              }
            ];
          };
        };
      };
    };

    cert-manager.Deployment.cert-manager-webhook = {
      metadata.labels =
        managed
        // {
          app = "cert-manager-webhook";
          "app.kubernetes.io/component" = "webhook";
          "app.kubernetes.io/instance" = "cert-manager";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels = {
          "app.kubernetes.io/component" = "webhook";
          "app.kubernetes.io/instance" = "cert-manager";
          "app.kubernetes.io/name" = "webhook";
        };
        strategy.type = "Recreate";
        template = {
          metadata.labels = {
            "app.kubernetes.io/component" = "webhook";
            "app.kubernetes.io/instance" = "cert-manager";
            "app.kubernetes.io/name" = "webhook";
          };
          spec = {
            serviceAccountName = "cert-manager-webhook";
            nodeSelector."kubernetes.io/os" = "linux";
            containers = [
              {
                name = "cert-manager-webhook";
                image = "quay.io/jetstack/cert-manager-webhook:${version}";
                args = [
                  "--v=2"
                  "--secure-port=10250"
                  "--dynamic-serving-ca-secret-namespace=$(POD_NAMESPACE)"
                  "--dynamic-serving-ca-secret-name=cert-manager-webhook-ca"
                  "--dynamic-serving-dns-names=cert-manager-webhook"
                  "--dynamic-serving-dns-names=cert-manager-webhook.$(POD_NAMESPACE)"
                  "--dynamic-serving-dns-names=cert-manager-webhook.$(POD_NAMESPACE).svc"
                ];
                env.POD_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                ports = [
                  {
                    name = "https";
                    containerPort = 10250;
                    protocol = "TCP";
                  }
                  {
                    name = "healthcheck";
                    containerPort = 6080;
                    protocol = "TCP";
                  }
                  {
                    name = "http-metrics";
                    containerPort = 9402;
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "64Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "256Mi";
                  };
                };
              }
            ];
          };
        };
      };
    };
  };
}
