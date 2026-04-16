{
  pkgs,
  config,
  lib,
  ...
}:
let
  # Pin versions for supply chain security
  lokiImage = "docker.io/grafana/loki:3.6.10";
  mimirImage = "docker.io/grafana/mimir:2.17.9";
  tempoImage = "docker.io/grafana/tempo:2.10.4";
  grafanaImage = "docker.io/grafana/grafana:12.4.3";
  alloyImage = "docker.io/grafana/alloy:v1.15.1";
  prometheusImage = "docker.io/prom/prometheus:v3.11.2";

  storageClass = "slow-hdd";

  # Sentry internal IP for node affinity
  sentryIP = "10.1.1.140";

  # Cluster DNS service IP
  clusterDNS = "10.0.0.10";

  # Loki config (monolithic mode, filesystem storage)
  # Reference: https://grafana.com/docs/loki/latest/configure/examples/
  lokiConfig = ''
    auth_enabled: false
    server:
      http_listen_port: 3100
      grpc_listen_port: 9096
      log_level: warn
    common:
      path_prefix: /loki
      storage:
        filesystem:
          chunks_directory: /loki/chunks
          rules_directory: /loki/rules
      replication_factor: 1
      ring:
        kvstore:
          store: inmemory
    schema_config:
      configs:
        - from: 2024-01-01
          store: tsdb
          object_store: filesystem
          schema: v13
          index:
            prefix: index_
            period: 24h
    storage_config:
      filesystem:
        directory: /loki/storage
      tsdb_shipper:
        active_index_directory: /loki/tsdb-index
        cache_location: /loki/tsdb-cache
    limits_config:
      retention_period: 30d
      allow_structured_metadata: true
      max_query_length: 721h
    compactor:
      working_directory: /loki/compactor
      compaction_interval: 10m
      retention_enabled: true
      delete_request_store: filesystem
    analytics:
      reporting_enabled: false
  '';

  # Mimir config (monolithic mode)
  # Reference: https://github.com/grafana/mimir/blob/main/development/mimir-monolithic-mode/config/mimir.yaml
  mimirConfig = ''
    target: all
    multitenancy_enabled: false
    server:
      http_listen_port: 9009
      grpc_listen_port: 9095
      log_level: warn
    activity_tracker:
      filepath: /mimir/activity/metrics-activity.log
    common:
      storage:
        backend: filesystem
        filesystem:
          dir: /mimir/storage
    blocks_storage:
      backend: filesystem
      filesystem:
        dir: /mimir/data/blocks
      tsdb:
        dir: /mimir/data/tsdb
      bucket_store:
        sync_dir: /mimir/data/sync
    compactor:
      data_dir: /mimir/data/compactor
    alertmanager:
      data_dir: /mimir/data/alertmanager
    ruler:
      rule_path: /mimir/data/rules-eval
    memberlist:
      bind_port: 7946
    distributor:
      ring:
        kvstore:
          store: memberlist
    ingester:
      ring:
        kvstore:
          store: memberlist
        replication_factor: 1
        final_sleep: 0s
    store_gateway:
      sharding_ring:
        replication_factor: 1
        kvstore:
          store: memberlist
  '';

  # Tempo config (monolithic mode)
  # Tempo config (monolithic mode)
  tempoConfig = ''
    server:
      http_listen_port: 3200
      grpc_listen_port: 9095
      log_level: warn
    distributor:
      receivers:
        otlp:
          protocols:
            http:
            grpc:
    ingester:
      max_block_duration: 5m
    compactor:
      compaction:
        block_retention: 720h
    metrics_generator:
      registry:
        external_labels:
          source: tempo
      storage:
        path: /data/generator/wal
    storage:
      trace:
        backend: local
        wal:
          path: /data/wal
        local:
          path: /data/blocks
    overrides:
      metrics_generator_processors:
        - service-graphs
        - span-metrics
  '';

  # Alloy config (collects logs + traces from all nodes)
  alloyConfig = ''
    // Discover Kubernetes pods and collect logs
    discovery.kubernetes "pods" {
      role = "pod"
    }

    // Collect container logs → Loki
    loki.source.kubernetes "logs" {
      targets    = discovery.kubernetes.pods.targets
      forward_to = [loki.write.loki.receiver]
    }

    // Write logs to Loki
    loki.write "loki" {
      endpoint {
        url = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
      }
    }

    // Scrape kubelet metrics
    discovery.kubernetes "nodes" {
      role = "node"
    }

    // Scrape cadvisor metrics
    prometheus.scrape "cadvisor" {
      targets = [
        {__address__ = "127.0.0.1:10250"},
      ]
      scheme               = "https"
      tls_config {
        insecure_skip_verify = true
      }
      bearer_token_file    = "/var/run/secrets/kubernetes.io/serviceaccount/token"
      scrape_interval      = "15s"
      forward_to           = [prometheus.remote_write.mimir.receiver]
    }

    // Remote write to Mimir
    prometheus.remote_write "mimir" {
      endpoint {
        url = "http://mimir.monitoring.svc.cluster.local:9009/api/v1/push"
      }
    }

    // Collect traces via OTLP
    otelcol.receiver.otlp "default" {
      grpc {
        endpoint = "0.0.0.0:4317"
      }
      http {
        endpoint = "0.0.0.0:4318"
      }
      output {
        traces = [otelcol.exporter.otlp.tempo.input]
      }
    }

    otelcol.exporter.otlp "tempo" {
      client {
        endpoint = "tempo.monitoring.svc.cluster.local:4317"
        tls {
          insecure = true
          insecure_skip_verify = true
        }
      }
    }

    // Collect Kubernetes events → Loki
    loki.source.kubernetes_events "events" {
      job_name   = "integrations/kubernetes/eventhandler"
      log_format = "logfmt"
      forward_to = [loki.write.loki.receiver]
    }

    // Self-monitoring: scrape Alloy metrics → Mimir
    prometheus.scrape "alloy_self" {
      targets = [
        {__address__ = "127.0.0.1:12345"},
      ]
      scrape_interval = "15s"
      forward_to      = [prometheus.remote_write.mimir.receiver]
    }
  '';

  # Prometheus config (scrapes cluster targets, remote_writes to Mimir)
  prometheusConfig = ''
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
      external_labels:
        cluster: nixos-k8s

    scrape_configs:
      - job_name: 'node-exporter'
        scrape_interval: 15s
        static_configs:
          - targets:
              - '10.1.1.110:9100'
              - '10.1.1.120:9100'
              - '10.1.1.130:9100'
              - '10.1.1.140:9100'

      - job_name: 'nvidia-exporter'
        scrape_interval: 15s
        static_configs:
          - targets:
              - '10.1.1.110:9400'
              - '10.1.1.120:9400'
              - '10.1.1.130:9400'

      - job_name: 'xmrig'
        scrape_interval: 30s
        static_configs:
          - targets:
              - '10.1.1.120:8081'
              - '10.1.1.120:8082'
              - '10.1.1.110:8082'
              - '10.1.1.140:8081'

      - job_name: 'lolminer'
        scrape_interval: 30s
        static_configs:
          - targets:
              - '10.1.1.130:4068'
              - '10.1.1.130:4069'
              - '10.1.1.120:4068'
              - '10.1.1.110:4069'

      - job_name: 'caddy'
        scrape_interval: 15s
        static_configs:
          - targets:
              - '10.1.1.110:2019'

      - job_name: 'kube-state-metrics'
        kubernetes_sd_configs:
          - role: endpoints
        relabel_configs:
          - source_labels: [__meta_kubernetes_service_name]
            regex: 'kube-state-metrics'
            action: keep

      - job_name: 'kubelet'
        scheme: https
        tls_config:
          insecure_skip_verify: true
        kubernetes_sd_configs:
          - role: node
        relabel_configs:
          - source_labels: [__meta_kubernetes_node_address_InternalIP]
            target_label: __address__
            replacement: "$1:10250"

      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            target_label: __address__
            regex: (.+)
            replacement: "$1"

    remote_write:
      - url: 'http://mimir.monitoring.svc.cluster.local:9009/api/v1/push'
  '';

  # Grafana datasources provisioning
  grafanaDatasources = {
    apiVersion = 1;
    datasources = [
      {
        name = "Mimir";
        type = "prometheus";
        url = "http://mimir.monitoring.svc.cluster.local:9009/prometheus";
        isDefault = true;
        editable = false;
        uid = "mimir";
      }
      {
        name = "Loki";
        type = "loki";
        url = "http://loki.monitoring.svc.cluster.local:3100";
        editable = false;
        uid = "loki";
      }
      {
        name = "Tempo";
        type = "tempo";
        url = "http://tempo.monitoring.svc.cluster.local:3200";
        editable = false;
        uid = "tempo";
      }
    ];
  };

  # Common node selector for sentry
  sentrySelector = { "kubernetes.io/hostname" = "sentry"; };

  # Common security context
  securityContext = {
    runAsNonRoot = true;
    runAsUser = 10001;
    runAsGroup = 10001;
    fsGroup = 10001;
    seccompProfile.type = "RuntimeDefault";
  };

  # Common container security
  containerSecurity = {
    allowPrivilegeEscalation = false;
    readOnlyRootFilesystem = true;
    capabilities.drop = [ "ALL" ];
  };

  # Common probes helper
  httpProbe = port: path: {
    httpGet = { inherit port path; };
    initialDelaySeconds = 30;
    periodSeconds = 10;
    timeoutSeconds = 5;
    failureThreshold = 3;
  };
in
{
  config.kubernetes.objects = {
    # ── Namespace ──────────────────────────────────────────────
    none.Namespace.monitoring = {
      metadata.labels = {
        name = "monitoring";
      };
    };

    # ── ServiceAccounts ────────────────────────────────────────
    monitoring.ServiceAccount.loki-sa = { };
    monitoring.ServiceAccount.mimir-sa = { };
    monitoring.ServiceAccount.tempo-sa = { };
    monitoring.ServiceAccount.grafana-sa = { };
    monitoring.ServiceAccount.alloy-sa = { };
    monitoring.ServiceAccount.prometheus-sa = { };

    # ── ClusterRole for Alloy (needs wide cluster access) ──────
    none.ClusterRole.alloy-cluster-role = {
      rules = [
        { apiGroups = [ "" ]; resources = [ "nodes" "nodes/metrics" "nodes/proxy" "pods" "services" "endpoints" "namespaces" ]; verbs = [ "get" "list" "watch" ]; }
        { apiGroups = [ "extensions" "networking.k8s.io" ]; resources = [ "ingresses" ]; verbs = [ "get" "list" "watch" ]; }
        { nonResourceURLs = [ "/metrics" "/metrics/cadvisor" ]; verbs = [ "get" ]; }
      ];
    };
    none.ClusterRoleBinding.alloy-cluster-rolebinding = {
      roleRef = { apiGroup = "rbac.authorization.k8s.io"; kind = "ClusterRole"; name = "alloy-cluster-role"; };
      subjects = [{ kind = "ServiceAccount"; name = "alloy-sa"; namespace = "monitoring"; }];
    };

    # ── ClusterRole for Prometheus ─────────────────────────────
    none.ClusterRole.prometheus-cluster-role = {
      rules = [
        { apiGroups = [ "" ]; resources = [ "nodes" "nodes/metrics" "nodes/proxy" "pods" "services" "endpoints" "namespaces" ]; verbs = [ "get" "list" "watch" ]; }
        { nonResourceURLs = [ "/metrics" ]; verbs = [ "get" ]; }
      ];
    };
    none.ClusterRoleBinding.prometheus-cluster-rolebinding = {
      roleRef = { apiGroup = "rbac.authorization.k8s.io"; kind = "ClusterRole"; name = "prometheus-cluster-role"; };
      subjects = [{ kind = "ServiceAccount"; name = "prometheus-sa"; namespace = "monitoring"; }];
    };

    # ── NetworkPolicies ────────────────────────────────────────
    monitoring.NetworkPolicy.default-deny-ingress = {
      spec = {
        podSelector = { };
        policyTypes = [ "Ingress" ];
      };
    };
    monitoring.NetworkPolicy.allow-internal = {
      spec = {
        podSelector = { };
        policyTypes = [ "Ingress" "Egress" ];
        ingress = [{ from = [{ namespaceSelector.matchLabels.name = "monitoring"; }]; }];
        egress = [
          { to = [{ namespaceSelector.matchLabels.name = "monitoring"; }]; }
          { to = [{ namespaceSelector = { }; podSelector.matchLabels."k8s-app" = "kube-dns"; }]; ports = [{ protocol = "UDP"; port = 53; } { protocol = "TCP"; port = 53; }]; }
        ];
      };
    };
    monitoring.NetworkPolicy.allow-caddy-to-grafana = {
      spec = {
        podSelector.matchLabels.app = "grafana";
        policyTypes = [ "Ingress" ];
        ingress = [{ from = [{ namespaceSelector.matchLabels.name = "ingress-system"; }]; ports = [{ protocol = "TCP"; port = 3000; }]; }];
      };
    };
    monitoring.NetworkPolicy.allow-alloy-kubelet = {
      spec = {
        podSelector.matchLabels.app = "alloy";
        policyTypes = [ "Egress" ];
        egress = [{ to = [{ ipBlock.cidr = "10.1.1.0/24"; }]; ports = [{ protocol = "TCP"; port = 10250; }]; }];
      };
    };

    # ── Loki ───────────────────────────────────────────────────
    monitoring.ConfigMap.loki-config.data."loki.yaml" = lokiConfig;

    monitoring.StatefulSet.loki = {
      metadata.labels.app = "loki";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        serviceName = "loki-headless";
        selector.matchLabels.app = "loki";
        template = {
          metadata.labels.app = "loki";
          spec = {
            nodeSelector = sentrySelector;
            securityContext = securityContext;
            serviceAccountName = "loki-sa";
            containers = {
              _namedlist = true;
              loki = {
                image = lokiImage;
                imagePullPolicy = "IfNotPresent";
                args = [ "-config.file=/etc/loki/loki.yaml" "-target=all" ];
                ports = [
                  { containerPort = 3100; name = "http"; protocol = "TCP"; }
                  { containerPort = 9096; name = "grpc"; protocol = "TCP"; }
                ];
                resources = {
                  requests = { cpu = "250m"; memory = "512Mi"; };
                  limits = { cpu = "1"; memory = "1Gi"; };
                };
                livenessProbe = httpProbe 3100 "/ready";
                readinessProbe = httpProbe 3100 "/ready";
                securityContext = containerSecurity;
                volumeMounts = {
                  _namedlist = true;
                  config = { mountPath = "/etc/loki"; readOnly = true; };
                  data = { mountPath = "/loki"; };
                };
              };
            };
            volumes = {
              _namedlist = true;
              config.configMap.name = "loki-config";
            };
          };
        };
        volumeClaimTemplates = [{
          metadata.name = "data";
          spec = {
            accessModes = [ "ReadWriteOnce" ];
            storageClassName = storageClass;
            resources.requests.storage = "50Gi";
          };
        }];
      };
    };

    monitoring.Service.loki = {
      metadata.labels.app = "loki";
      spec = {
        type = "ClusterIP";
        ports = [
          { name = "http"; port = 3100; targetPort = 3100; protocol = "TCP"; }
          { name = "grpc"; port = 9096; targetPort = 9096; protocol = "TCP"; }
        ];
        selector.app = "loki";
      };
    };
    monitoring.Service.loki-headless = {
      metadata.labels.app = "loki";
      spec = {
        type = "ClusterIP";
        clusterIP = "None";
        ports = [{ name = "http"; port = 3100; targetPort = 3100; protocol = "TCP"; }];
        selector.app = "loki";
      };
    };

    # ── Mimir ──────────────────────────────────────────────────
    monitoring.ConfigMap.mimir-config.data."mimir.yaml" = mimirConfig;

    monitoring.StatefulSet.mimir = {
      metadata.labels.app = "mimir";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        serviceName = "mimir-headless";
        selector.matchLabels.app = "mimir";
        template = {
          metadata.labels.app = "mimir";
          spec = {
            nodeSelector = sentrySelector;
            securityContext = securityContext;
            serviceAccountName = "mimir-sa";
            containers = {
              _namedlist = true;
              mimir = {
                image = mimirImage;
                imagePullPolicy = "IfNotPresent";
                args = [ "-config.file=/etc/mimir/mimir.yaml" "-target=all" ];
                ports = [
                  { containerPort = 9009; name = "http"; protocol = "TCP"; }
                  { containerPort = 9095; name = "grpc"; protocol = "TCP"; }
                  { containerPort = 7946; name = "memberlist"; protocol = "TCP"; }
                ];
                resources = {
                  requests = { cpu = "500m"; memory = "1Gi"; };
                  limits = { cpu = "2"; memory = "4Gi"; };
                };
                livenessProbe = httpProbe 9009 "/ready";
                readinessProbe = httpProbe 9009 "/ready";
                securityContext = containerSecurity;
                volumeMounts = {
                  _namedlist = true;
                  config = { mountPath = "/etc/mimir"; readOnly = true; };
                  data = { mountPath = "/mimir"; };
                  activity = { mountPath = "/mimir/activity"; };
                };
              };
            };
            volumes = {
              _namedlist = true;
              config.configMap.name = "mimir-config";
              activity.emptyDir = { };
            };
          };
        };
        volumeClaimTemplates = [{
          metadata.name = "data";
          spec = {
            accessModes = [ "ReadWriteOnce" ];
            storageClassName = storageClass;
            resources.requests.storage = "100Gi";
          };
        }];
      };
    };

    monitoring.Service.mimir = {
      metadata.labels.app = "mimir";
      spec = {
        type = "ClusterIP";
        ports = [
          { name = "http"; port = 9009; targetPort = 9009; protocol = "TCP"; }
          { name = "grpc"; port = 9095; targetPort = 9095; protocol = "TCP"; }
        ];
        selector.app = "mimir";
      };
    };
    monitoring.Service.mimir-headless = {
      metadata.labels.app = "mimir";
      spec = {
        type = "ClusterIP";
        clusterIP = "None";
        ports = [{ name = "http"; port = 9009; targetPort = 9009; protocol = "TCP"; }];
        selector.app = "mimir";
      };
    };

    # ── Tempo ──────────────────────────────────────────────────
    monitoring.ConfigMap.tempo-config.data."tempo.yaml" = tempoConfig;

    monitoring.StatefulSet.tempo = {
      metadata.labels.app = "tempo";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        serviceName = "tempo-headless";
        selector.matchLabels.app = "tempo";
        template = {
          metadata.labels.app = "tempo";
          spec = {
            nodeSelector = sentrySelector;
            securityContext = securityContext;
            serviceAccountName = "tempo-sa";
            containers = {
              _namedlist = true;
              tempo = {
                image = tempoImage;
                imagePullPolicy = "IfNotPresent";
                args = [ "-config.file=/etc/tempo/tempo.yaml" ];
                ports = [
                  { containerPort = 3200; name = "http"; protocol = "TCP"; }
                  { containerPort = 4317; name = "otlp-grpc"; protocol = "TCP"; }
                  { containerPort = 4318; name = "otlp-http"; protocol = "TCP"; }
                ];
                resources = {
                  requests = { cpu = "250m"; memory = "512Mi"; };
                  limits = { cpu = "1"; memory = "2Gi"; };
                };
                livenessProbe = httpProbe 3200 "/ready";
                readinessProbe = httpProbe 3200 "/ready";
                securityContext = containerSecurity;
                volumeMounts = {
                  _namedlist = true;
                  config = { mountPath = "/etc/tempo"; readOnly = true; };
                  data = { mountPath = "/data"; };
                };
              };
            };
            volumes = {
              _namedlist = true;
              config.configMap.name = "tempo-config";
            };
          };
        };
        volumeClaimTemplates = [{
          metadata.name = "data";
          spec = {
            accessModes = [ "ReadWriteOnce" ];
            storageClassName = storageClass;
            resources.requests.storage = "50Gi";
          };
        }];
      };
    };

    monitoring.Service.tempo = {
      metadata.labels.app = "tempo";
      spec = {
        type = "ClusterIP";
        ports = [
          { name = "http"; port = 3200; targetPort = 3200; protocol = "TCP"; }
          { name = "otlp-grpc"; port = 4317; targetPort = 4317; protocol = "TCP"; }
          { name = "otlp-http"; port = 4318; targetPort = 4318; protocol = "TCP"; }
        ];
        selector.app = "tempo";
      };
    };
    monitoring.Service.tempo-headless = {
      metadata.labels.app = "tempo";
      spec = {
        type = "ClusterIP";
        clusterIP = "None";
        ports = [{ name = "http"; port = 3200; targetPort = 3200; protocol = "TCP"; }];
        selector.app = "tempo";
      };
    };

    # ── Grafana ────────────────────────────────────────────────
    monitoring.ConfigMap.grafana-datasources.data."datasources.yaml" =
      builtins.toJSON grafanaDatasources;

    monitoring.Deployment.grafana = {
      metadata.labels.app = "grafana";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "grafana";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = { maxSurge = 0; maxUnavailable = 1; };
        };
        template = {
          metadata.labels.app = "grafana";
          spec = {
            nodeSelector = sentrySelector;
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 10001;
              runAsGroup = 10001;
              fsGroup = 10001;
              seccompProfile.type = "RuntimeDefault";
            };
            serviceAccountName = "grafana-sa";
            containers = {
              _namedlist = true;
              grafana = {
                image = grafanaImage;
                imagePullPolicy = "IfNotPresent";
                env = {
                  _namedlist = true;
                  GF_SECURITY_ADMIN_USER.value = "admin";
                  GF_SECURITY_ADMIN_PASSWORD.value = "admin";
                  GF_USERS_ALLOW_SIGN_UP.value = "false";
                  GF_AUTH_ANONYMOUS_ENABLED.value = "false";
                  GF_LOG_MODE.value = "console";
                  GF_LOG_LEVEL.value = "warn";
                  GF_SERVER_ROOT_URL.value = "http://grafana.monitoring.svc.cluster.local:3000";
                };
                ports = [{ containerPort = 3000; name = "http"; protocol = "TCP"; }];
                resources = {
                  requests = { cpu = "100m"; memory = "128Mi"; };
                  limits = { cpu = "500m"; memory = "512Mi"; };
                };
                livenessProbe = httpProbe 3000 "/api/health";
                readinessProbe = httpProbe 3000 "/api/health";
                securityContext = containerSecurity;
                volumeMounts = {
                  _namedlist = true;
                  datasources = { mountPath = "/etc/grafana/provisioning/datasources"; readOnly = true; };
                  dashboards-provider = { mountPath = "/etc/grafana/provisioning/dashboards"; readOnly = true; };
                  dashboards = { mountPath = "/var/lib/grafana/dashboards"; readOnly = true; };
                  data = { mountPath = "/var/lib/grafana"; };
                };
              };
            };
            volumes = {
              _namedlist = true;
              datasources.configMap.name = "grafana-datasources";
              dashboards-provider.configMap.name = "grafana-dashboards-provider";
              dashboards.configMap.name = "grafana-dashboards";
              data.persistentVolumeClaim.claimName = "grafana-data";
            };
          };
        };
      };
    };

    monitoring.PersistentVolumeClaim.grafana-data = {
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = storageClass;
        resources.requests.storage = "10Gi";
      };
    };

    monitoring.Service.grafana = {
      metadata.labels.app = "grafana";
      spec = {
        type = "ClusterIP";
        ports = [{ name = "http"; port = 3000; targetPort = 3000; protocol = "TCP"; }];
        selector.app = "grafana";
      };
    };

    monitoring.Ingress.grafana = {
      metadata.annotations."caddy.ingress.kubernetes.io/disable-ssl-redirect" = "true";
      spec = {
        ingressClassName = "caddy";
        rules = [
          {
            host = "grafana.lan";
            http.paths = [{
              path = "/";
              pathType = "Prefix";
              backend.service = { name = "grafana"; port.number = 3000; };
            }];
          }
          {
            host = "grafana.cluster.local";
            http.paths = [{
              path = "/";
              pathType = "Prefix";
              backend.service = { name = "grafana"; port.number = 3000; };
            }];
          }
        ];
      };
    };

    # ── Alloy (DaemonSet — one per node) ───────────────────────
    monitoring.ConfigMap.alloy-config.data."config.alloy" = alloyConfig;

    monitoring.DaemonSet.alloy = {
      metadata.labels.app = "alloy";
      spec = {
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "alloy";
        template = {
          metadata.labels.app = "alloy";
          spec = {
            serviceAccountName = "alloy-sa";
            hostNetwork = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            tolerations = [
              { key = "node-role.kubernetes.io/control-plane"; effect = "NoSchedule"; }
              { key = "node-role.kubernetes.io/master"; effect = "NoSchedule"; }
            ];
            securityContext = {
              runAsUser = 0;
              runAsGroup = 0;
              seccompProfile.type = "RuntimeDefault";
            };
            containers = {
              _namedlist = true;
              alloy = {
                image = alloyImage;
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
                ports = [{ containerPort = 12345; name = "http"; protocol = "TCP"; }];
                resources = {
                  requests = { cpu = "100m"; memory = "256Mi"; };
                  limits = { cpu = "500m"; memory = "512Mi"; };
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = [ "ALL" ];
                };
                volumeMounts = {
                  _namedlist = true;
                  config = { mountPath = "/etc/alloy"; readOnly = true; };
                  data = { mountPath = "/var/lib/alloy"; };
                  "var-log" = { mountPath = "/var/log"; readOnly = true; };
                  "docker-containers" = { mountPath = "/var/lib/docker/containers"; readOnly = true; };
                  "containerd-containers" = { mountPath = "/var/lib/containerd"; readOnly = true; };
                };
              };
            };
            volumes = {
              _namedlist = true;
              config.configMap.name = "alloy-config";
              data.emptyDir = { };
              "var-log" = { hostPath.path = "/var/log"; hostPath.type = "DirectoryOrCreate"; };
              "docker-containers" = { hostPath.path = "/var/lib/docker/containers"; hostPath.type = "DirectoryOrCreate"; };
              "containerd-containers" = { hostPath.path = "/var/lib/containerd"; hostPath.type = "DirectoryOrCreate"; };
            };
          };
        };
      };
    };

    # ── Prometheus (scrapes targets, remote_writes to Mimir) ───
    monitoring.ConfigMap.prometheus-config.data."prometheus.yml" = prometheusConfig;

    monitoring.Deployment.prometheus = {
      metadata.labels.app = "prometheus";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "prometheus";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = { maxSurge = 0; maxUnavailable = 1; };
        };
        template = {
          metadata.labels.app = "prometheus";
          spec = {
            nodeSelector = sentrySelector;
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
                image = prometheusImage;
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--config.file=/etc/prometheus/prometheus.yml"
                  "--storage.tsdb.path=/prometheus"
                  "--storage.tsdb.retention.time=2h"
                  "--storage.tsdb.retention.size=1GB"
                  "--web.enable-remote-write-receiver"
                  "--web.listen-address=0.0.0.0:9090"
                ];
                ports = [{ containerPort = 9090; name = "http"; protocol = "TCP"; }];
                resources = {
                  requests = { cpu = "250m"; memory = "512Mi"; };
                  limits = { cpu = "1"; memory = "2Gi"; };
                };
                livenessProbe = httpProbe 9090 "/-/healthy";
                readinessProbe = httpProbe 9090 "/-/ready";
                securityContext = containerSecurity;
                volumeMounts = {
                  _namedlist = true;
                  config = { mountPath = "/etc/prometheus"; readOnly = true; };
                  data = { mountPath = "/prometheus"; };
                };
              };
            };
            volumes = {
              _namedlist = true;
              config.configMap.name = "prometheus-config";
              data.emptyDir = { }; # Short retention — Mimir handles long-term
            };
          };
        };
      };
    };

    monitoring.Service.prometheus = {
      metadata.labels.app = "prometheus";
      spec = {
        type = "ClusterIP";
        ports = [{ name = "http"; port = 9090; targetPort = 9090; protocol = "TCP"; }];
        selector.app = "prometheus";
      };
    };

    # ── kube-state-metrics ─────────────────────────────────────
    monitoring.ServiceAccount.kube-state-metrics-sa = { };
    none.ClusterRole.kube-state-metrics-role = {
      rules = [
        { apiGroups = [ "" ]; resources = [ "configmaps" "secrets" "nodes" "pods" "limitranges" "replicationcontrollers" "resourcequotas" "services" ]; verbs = [ "list" "watch" ]; }
        { apiGroups = [ "apps" ]; resources = [ "controllerrevisions" "daemonsets" "deployments" "replicasets" "statefulsets" ]; verbs = [ "list" "watch" ]; }
        { apiGroups = [ "batch" ]; resources = [ "cronjobs" "jobs" ]; verbs = [ "list" "watch" ]; }
        { apiGroups = [ "autoscaling" ]; resources = [ "horizontalpodautoscalers" ]; verbs = [ "list" "watch" ]; }
        { apiGroups = [ "policy" ]; resources = [ "poddisruptionbudgets" ]; verbs = [ "list" "watch" ]; }
        { apiGroups = [ "storage.k8s.io" ]; resources = [ "storageclasses" "volumeattachments" ]; verbs = [ "list" "watch" ]; }
      ];
    };
    none.ClusterRoleBinding.kube-state-metrics-rolebinding = {
      roleRef = { apiGroup = "rbac.authorization.k8s.io"; kind = "ClusterRole"; name = "kube-state-metrics-role"; };
      subjects = [{ kind = "ServiceAccount"; name = "kube-state-metrics-sa"; namespace = "monitoring"; }];
    };
    monitoring.Deployment.kube-state-metrics = {
      metadata.labels.app = "kube-state-metrics";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "kube-state-metrics";
        template = {
          metadata.labels.app = "kube-state-metrics";
          spec = {
            nodeSelector = { "kubernetes.io/hostname" = "sentry"; };
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
                image = "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.15.0";
                imagePullPolicy = "IfNotPresent";
                args = [ "--port=8080" "--metric-labels-allowlist=nodes=[kubernetes.io/hostname]" ];
                ports = [{ containerPort = 8080; name = "http"; protocol = "TCP"; }];
                resources = {
                  requests = { cpu = "100m"; memory = "128Mi"; };
                  limits = { cpu = "500m"; memory = "512Mi"; };
                };
                livenessProbe = { httpGet = { path = "/healthz"; port = 8080; }; initialDelaySeconds = 5; periodSeconds = 10; };
                readinessProbe = { httpGet = { path = "/"; port = 8080; }; initialDelaySeconds = 5; periodSeconds = 10; };
                securityContext = { allowPrivilegeEscalation = false; readOnlyRootFilesystem = true; capabilities.drop = [ "ALL" ]; };
              };
            };
          };
        };
      };
    };
    monitoring.Service.kube-state-metrics = {
      metadata.labels.app = "kube-state-metrics";
      spec = {
        type = "ClusterIP";
        ports = [{ name = "http"; port = 8080; targetPort = 8080; protocol = "TCP"; }];
        selector.app = "kube-state-metrics";
      };
    };

    # ── PDBs ───────────────────────────────────────────────────
    monitoring.PodDisruptionBudget.loki-pdb = {
      spec.minAvailable = 1;
      spec.selector.matchLabels.app = "loki";
    };
    monitoring.PodDisruptionBudget.mimir-pdb = {
      spec.minAvailable = 1;
      spec.selector.matchLabels.app = "mimir";
    };
    monitoring.PodDisruptionBudget.grafana-pdb = {
      spec.minAvailable = 1;
      spec.selector.matchLabels.app = "grafana";
    };
  };
}
