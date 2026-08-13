{
  monitoring,
  cluster,
  ...
}: {
  config.kubernetes.objects = {
    # -- Metrics Server APIService -----------------------------------------
    # Source: metrics-server-apiservice.yaml
    none.APIService.v1beta1-metrics-k8s-io = {
      metadata.name = "v1beta1.metrics.k8s.io";
      spec = {
        service = {
          name = "metrics-server";
          namespace = "kube-system";
          port = 443;
        };
        group = "metrics.k8s.io";
        version = "v1beta1";
        insecureSkipTLSVerify = true;
        groupPriorityMinimum = 100;
        versionPriority = 100;
      };
    };

    # -- Metrics Server Network Policy -------------------------------------
    # Source: metrics-server-network-policy.yaml
    kube-system.NetworkPolicy.allow-metrics-server-kubelet = {
      spec = {
        podSelector.matchLabels."k8s-app" = "metrics-server";
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{ipBlock.cidr = cluster.subnet;}];
            ports = [
              {
                protocol = "TCP";
                port = 10250;
              }
            ];
          }
          {
            to = [{namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";}];
            ports = [
              {
                protocol = "UDP";
                port = 53;
              }
              {
                protocol = "TCP";
                port = 53;
              }
            ];
          }
        ];
      };
    };

    # -- Prometheus Adapter (custom-metrics namespace) ---------------------
    # Source: prometheus-adapter-namespace.yaml
    none.Namespace.custom-metrics = {
      metadata.labels =
        monitoring.managed
        // {
          name = "custom-metrics";
          "pod-security.kubernetes.io/enforce" = "baseline";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        };
    };

    custom-metrics.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };

    # Source: prometheus-adapter-rbac.yaml
    custom-metrics.ServiceAccount.prometheus-adapter = {};

    none.ClusterRole.prometheus-adapter-server-resources = {
      rules = [
        {
          apiGroups = [""];
          resources = [
            "namespaces"
            "pods"
            "nodes"
          ];
          verbs = [
            "get"
            "list"
            "watch"
          ];
        }
      ];
    };

    none.ClusterRoleBinding.prometheus-adapter-auth-delegator = {
      metadata.name = "prometheus-adapter:system:auth-delegator";
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "system:auth-delegator";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "prometheus-adapter";
          namespace = "custom-metrics";
        }
      ];
    };

    none.ClusterRoleBinding.prometheus-adapter-resource-reader = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "prometheus-adapter-server-resources";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "prometheus-adapter";
          namespace = "custom-metrics";
        }
      ];
    };

    kube-system.RoleBinding.prometheus-adapter-auth-reader = {
      metadata.name = "prometheus-adapter-auth-reader";
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "Role";
        name = "extension-apiserver-authentication-reader";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "prometheus-adapter";
          namespace = "custom-metrics";
        }
      ];
    };

    # Source: prometheus-adapter-config.yaml
    custom-metrics.ConfigMap.prometheus-adapter-config.data."config.yaml" = ''
      resourceRules:
        cpu:
          containerLabel: container
          containerQuery: |
            sum by (container) (
              rate(container_cpu_usage_seconds_total{container!="", container!="POD"}[5m])
            )
          nodeQuery: |
            sum by (node) (
              rate(node_cpu_seconds_total{mode!="idle"}[5m])
            )
          resources:
            overrides:
              node:
                resource: node
              namespace:
                resource: namespace
              pod:
                resource: pod
        memory:
          containerLabel: container
          containerQuery: |
            sum by (container) (
              container_memory_working_set_bytes{container!="", container!="POD"}
            )
          nodeQuery: |
            sum by (node) (
              node_memory_MemAvailable_bytes
            )
          resources:
            overrides:
              node:
                resource: node
              namespace:
                resource: namespace
              pod:
                resource: pod
        window: 5m
    '';

    # Source: prometheus-adapter-deployment.yaml
    custom-metrics.Deployment.prometheus-adapter = {
      metadata.labels = monitoring.managed // {name = "prometheus-adapter";};
      spec = {
        replicas = 1;
        selector.matchLabels.name = "prometheus-adapter";
        template = {
          metadata.labels = monitoring.managed // {name = "prometheus-adapter";};
          spec = {
            serviceAccountName = "prometheus-adapter";
            hostNetwork = true;
            containers = {
              _namedlist = true;
              prometheus-adapter = {
                image = "registry.k8s.io/prometheus-adapter/prometheus-adapter:v0.12.0";
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--prometheus-url=http://prometheus.monitoring.svc:9090/"
                  "--metrics-relist-interval=1m"
                  "--v=4"
                  "--config=/etc/adapter/config.yaml"
                ];
                ports = [
                  {
                    containerPort = 443;
                    name = "https";
                    protocol = "TCP";
                  }
                ];
                volumeMounts = {
                  _namedlist = true;
                  config = {
                    mountPath = "/etc/adapter/";
                    readOnly = true;
                  };
                };
                livenessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = "https";
                    scheme = "HTTPS";
                  };
                  initialDelaySeconds = 30;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = "https";
                    scheme = "HTTPS";
                  };
                  initialDelaySeconds = 30;
                };
                securityContext.runAsUser = 0;
              };
            };
            volumes = {
              _namedlist = true;
              config.configMap.name = "prometheus-adapter-config";
            };
          };
        };
      };
    };

    custom-metrics.Service.prometheus-adapter = {
      metadata.labels = monitoring.managed // {name = "prometheus-adapter";};
      spec = {
        ports = [
          {
            name = "https";
            port = 443;
            targetPort = "https";
          }
        ];
        selector.name = "prometheus-adapter";
      };
    };

    # APIServices for prometheus-adapter
    none.APIService.v1beta1-custom-metrics-k8s-io = {
      metadata.name = "v1beta1.custom.metrics.k8s.io";
      spec = {
        service = {
          name = "prometheus-adapter";
          namespace = "custom-metrics";
        };
        group = "custom.metrics.k8s.io";
        version = "v1beta1";
        insecureSkipTLSVerify = true;
        groupPriorityMinimum = 100;
        versionPriority = 100;
      };
    };

    none.APIService.v1beta2-custom-metrics-k8s-io = {
      metadata.name = "v1beta2.custom.metrics.k8s.io";
      spec = {
        service = {
          name = "prometheus-adapter";
          namespace = "custom-metrics";
        };
        group = "custom.metrics.k8s.io";
        version = "v1beta2";
        insecureSkipTLSVerify = true;
        groupPriorityMinimum = 100;
        versionPriority = 100;
      };
    };
  };
}
