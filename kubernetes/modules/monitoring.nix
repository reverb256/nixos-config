{
  cluster,
  config,
  lib,
  nexusPreferredAffinity,
  ...
}: let
  # Pin versions for supply chain security
  lokiImage = "docker.io/grafana/loki:3.7.1";
  mimirImage = "docker.io/grafana/mimir:3.0.6";
  tempoImage = "docker.io/grafana/tempo:2.10.5";
  grafanaImage = "docker.io/grafana/grafana:13.0.1";
  alloyImage = "docker.io/grafana/alloy:v1.16.1";
  prometheusImage = "docker.io/prom/prometheus:v3.11.3";

  storageClass = "slow-hdd";

  # Cluster host IPs — single source of truth from cluster.nix
  hostIPs = cluster.hosts;

  # Cluster DNS service IP (CoreDNS)
  clusterDNS = cluster.kubernetes.clusterDnsIP;

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
      retention_period: 7d
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
              endpoint: 0.0.0.0:4318
            grpc:
              endpoint: 0.0.0.0:4317
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

    // PII stripping pipeline (MLSEC Phase 3.2)
    // Redacts emails, bearer tokens, API keys before Loki write
    loki.process "pii_strip" {
      // Strip email addresses
      stage.match {
        selector = "{job=~\".+\"}"
        stage.regex {
          expression = "(?i)[a-z0-9._%+\\-]+@[a-z0-9.\\-]+\\.[a-z]{2,}"
          source     = "entry"
        }
        stage.replace {
          expression = "(?i)[a-z0-9._%+\\-]+@[a-z0-9.\\-]+\\.[a-z]{2,}"
          replace    = "[REDACTED-EMAIL]"
        }
      }

      // Strip bearer/token patterns
      stage.match {
        selector = "{job=~\".+\"}"
        stage.regex {
          expression = "(?i)bearer\\s+[A-Za-z0-9\\-._~+/]+=*"
          source     = "entry"
        }
        stage.replace {
          expression = "(?i)(bearer)\\s+[A-Za-z0-9\\-._~+/]+=*"
          replace    = "''${1} [REDACTED-TOKEN]"
        }
      }

      // Strip API keys and long hex tokens
      stage.match {
        selector = "{job=~\".+\"}"
        stage.regex {
          expression = "(?i)(api[_\\-]?key|token|secret|password|apikey)[\"']?\\s*[:=]\\s*[\"']?[A-Za-z0-9\\-._~+/]{16,}"
          source     = "entry"
        }
        stage.replace {
          expression = "(?i)(api[_\\-]?key|token|secret|password|apikey)([\"']?\\s*[:=]\\s*[\"']?)[A-Za-z0-9\\-._~+/]{16,}"
          replace    = "''${1}''${2}[REDACTED]"
        }
      }

      forward_to = [loki.write.loki.receiver]
    }

    // Collect container logs → PII stripping → Loki
    loki.source.kubernetes "logs" {
      targets    = discovery.kubernetes.pods.targets
      forward_to = [loki.process.pii_strip.receiver]
    }

    // Collect host journald logs -> PII stripping -> Loki
    loki.source.journal "host_journal" {
      path       = "/var/log/journal"
      forward_to = [loki.process.pii_strip.receiver]
      labels     = {
        job = "systemd-journal",
      }
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

    // Collect Kubernetes events → PII stripping → Loki
    loki.source.kubernetes_events "events" {
      job_name   = "integrations/kubernetes/eventhandler"
      log_format = "logfmt"
      forward_to = [loki.process.pii_strip.receiver]
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
              - '${hostIPs.zephyr.ip}:9100'
              - '${hostIPs.nexus.ip}:9100'
              - '${hostIPs.forge.ip}:9100'
              - '${hostIPs.sentry.ip}:9100'

      - job_name: 'nvidia-exporter'
        scrape_interval: 15s
        static_configs:
          - targets:
              - '${hostIPs.zephyr.ip}:9400'
              - '${hostIPs.nexus.ip}:9400'
              - '${hostIPs.forge.ip}:9400'


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
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
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

      - job_name: 'etcd'
        scrape_interval: 30s
        static_configs:
          - targets:
              - '${hostIPs.zephyr.ip}:2379'
              - '${hostIPs.nexus.ip}:2379'
              - '${hostIPs.sentry.ip}:2379'
        scheme: https
        tls_config:
          insecure_skip_verify: true

    alerting:
      alertmanagers:
        - static_configs:
            - targets:
                - 'alertmanager.monitoring.svc.cluster.local:9093'

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
  sentrySelector = {
    "kubernetes.io/hostname" = "sentry";
  };

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
    capabilities.drop = ["ALL"];
  };

  # Common probes helper
  httpProbe = port: path: {
    httpGet = {inherit port path;};
    initialDelaySeconds = 30;
    periodSeconds = 10;
    timeoutSeconds = 5;
    failureThreshold = 3;
  };

  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects = {
    # ── Namespace ──────────────────────────────────────────────
    none.Namespace.monitoring = {
      metadata.labels = {
        name = "monitoring";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    # ── ServiceAccounts ────────────────────────────────────────
    monitoring.ServiceAccount.loki-sa = {};
    monitoring.ServiceAccount.mimir-sa = {};
    monitoring.ServiceAccount.tempo-sa = {};
    monitoring.ServiceAccount.grafana-sa = {};
    monitoring.ServiceAccount.alloy-sa = {};
    monitoring.ServiceAccount.prometheus-sa = {};

    # ── ClusterRole for Alloy (needs wide cluster access) ──────
    none.ClusterRole.alloy-cluster-role = {
      rules = [
        {
          apiGroups = [""];
          resources = [
            "nodes"
            "nodes/metrics"
            "nodes/proxy"
            "pods"
            "pods/log"
            "services"
            "endpoints"
            "namespaces"
          ];
          verbs = [
            "get"
            "list"
            "watch"
          ];
        }
        {
          apiGroups = [""];
          resources = ["events"];
          verbs = ["get" "list" "watch"];
        }
        {
          apiGroups = [
            "networking.k8s.io"
          ];
          resources = ["ingresses"];
          verbs = [
            "get"
            "list"
            "watch"
          ];
        }
        {
          nonResourceURLs = [
            "/metrics"
            "/metrics/cadvisor"
          ];
          verbs = ["get"];
        }
      ];
    };
    none.ClusterRoleBinding.alloy-cluster-rolebinding = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "alloy-cluster-role";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "alloy-sa";
          namespace = "monitoring";
        }
      ];
    };

    # ── ClusterRole for Prometheus ─────────────────────────────
    none.ClusterRole.prometheus-cluster-role = {
      rules = [
        {
          apiGroups = [""];
          resources = [
            "nodes"
            "nodes/metrics"
            "nodes/proxy"
            "pods"
            "services"
            "endpoints"
            "namespaces"
          ];
          verbs = [
            "get"
            "list"
            "watch"
          ];
        }
        {
          nonResourceURLs = ["/metrics"];
          verbs = ["get"];
        }
      ];
    };
    none.ClusterRoleBinding.prometheus-cluster-rolebinding = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "prometheus-cluster-role";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "prometheus-sa";
          namespace = "monitoring";
        }
      ];
    };

    # ── NetworkPolicies ────────────────────────────────────────
    monitoring.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };
    monitoring.NetworkPolicy.allow-internal = {
      spec = {
        podSelector = {};
        policyTypes = [
          "Ingress"
          "Egress"
        ];
        ingress = [{from = [{namespaceSelector.matchLabels.name = "monitoring";}];}];
        egress = [
          {to = [{namespaceSelector.matchLabels.name = "monitoring";}];}
          {
            to = [
              {
                namespaceSelector = {};
                podSelector.matchLabels."k8s-app" = "kube-dns";
              }
            ];
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
    monitoring.NetworkPolicy.allow-caddy-to-grafana = {
      spec = {
        podSelector.matchLabels.app = "grafana";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{namespaceSelector.matchLabels.name = "ingress-system";}];
            ports = [
              {
                protocol = "TCP";
                port = 3000;
              }
            ];
          }
        ];
      };
    };

    monitoring.NetworkPolicy.allow-dashboard-to-prometheus = {
      spec = {
        podSelector.matchLabels.app = "prometheus";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{namespaceSelector.matchLabels.name = "dashboard";}];
            ports = [
              {
                protocol = "TCP";
                port = 9090;
              }
            ];
          }
        ];
      };
    };
    monitoring.NetworkPolicy.allow-alloy-kubelet = {
      spec = {
        podSelector.matchLabels.app = "alloy";
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
        ];
      };
    };

    # ── Loki ───────────────────────────────────────────────────
    monitoring.ConfigMap.loki-config.data."loki.yaml" = lokiConfig;

    monitoring.StatefulSet.loki = {
      metadata.labels = managed // {app = "loki";};
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
            nodeSelector = sentrySelector;
            inherit securityContext;
            serviceAccountName = "loki-sa";
            containers = {
              _namedlist = true;
              loki = {
                image = lokiImage;
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
                livenessProbe = httpProbe 3100 "/ready";
                readinessProbe = httpProbe 3100 "/ready";
                securityContext = containerSecurity;
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
              storageClassName = storageClass;
              resources.requests.storage = "50Gi";
            };
          }
        ];
      };
    };

    monitoring.Service.loki = {
      metadata.labels = managed // {app = "loki";};
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
      metadata.labels = managed // {app = "loki";};
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

    # ── Mimir ──────────────────────────────────────────────────
    monitoring.ConfigMap.mimir-config.data."mimir.yaml" = mimirConfig;

    monitoring.StatefulSet.mimir = {
      metadata.labels = managed // {app = "mimir";};
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
            nodeSelector = sentrySelector;
            inherit securityContext;
            serviceAccountName = "mimir-sa";
            containers = {
              _namedlist = true;
              mimir = {
                image = mimirImage;
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
                livenessProbe = httpProbe 9009 "/ready";
                readinessProbe = httpProbe 9009 "/ready";
                securityContext = containerSecurity;
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
              storageClassName = storageClass;
              resources.requests.storage = "100Gi";
            };
          }
        ];
      };
    };

    monitoring.Service.mimir = {
      metadata.labels = managed // {app = "mimir";};
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
      metadata.labels = managed // {app = "mimir";};
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

    # ── Tempo ──────────────────────────────────────────────────
    monitoring.ConfigMap.tempo-config.data."tempo.yaml" = tempoConfig;

    monitoring.StatefulSet.tempo = {
      metadata.labels = managed // {app = "tempo";};
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
            nodeSelector = sentrySelector;
            inherit securityContext;
            serviceAccountName = "tempo-sa";
            containers = {
              _namedlist = true;
              tempo = {
                image = tempoImage;
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
                livenessProbe = httpProbe 3200 "/ready";
                readinessProbe = httpProbe 3200 "/ready";
                securityContext = containerSecurity;
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
              storageClassName = storageClass;
              resources.requests.storage = "50Gi";
            };
          }
        ];
      };
    };

    monitoring.Service.tempo = {
      metadata.labels = managed // {app = "tempo";};
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
      metadata.labels = managed // {app = "tempo";};
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

    # ── Grafana admin secret ──────────────────────────────────
    # Populated by kubectl-apply-k8s-secrets from agenix:
    #   admin-password ← /run/agenix/grafana-admin-password
    # grafana-oidc-secret populated by kubectl-apply-k8s-secrets from agenix
    monitoring.Secret.grafana-oidc-secret = {
      type = "Opaque";
      stringData = {};
    };

    monitoring.Secret.grafana-admin-secret = {
      type = "Opaque";
      stringData."admin-password" = "";
    };

    # ── Grafana ────────────────────────────────────────────────
    monitoring.ConfigMap.grafana-datasources.data."datasources.yaml" =
      builtins.toJSON grafanaDatasources;

    monitoring.Deployment.grafana = {
      metadata.labels = managed // {app = "grafana";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "grafana";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 1;
            maxUnavailable = 0;
          };
        };
        template = {
          metadata = {
            labels.app = "grafana";
          };
          spec = {
            affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution = [
              {
                labelSelector.matchLabels.app = "grafana";
                topologyKey = "kubernetes.io/hostname";
              }
            ];
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
                  GF_SECURITY_ADMIN_PASSWORD.valueFrom.secretKeyRef = {
                    name = "grafana-admin-secret";
                    key = "admin-password";
                  };
                  GF_USERS_ALLOW_SIGN_UP.value = "false";
                  GF_AUTH_ANONYMOUS_ENABLED.value = "false";
                  GF_LOG_MODE.value = "console";
                  GF_LOG_LEVEL.value = "warn";
                  GF_SERVER_ROOT_URL.value = "http://grafana.monitoring.svc.cluster.local:3000";
                  # MLSEC Phase 3.5: RBAC hardening
                  GF_AUTH_DISABLE_LOGIN_FORM.value = "false";
                  GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION.value = "true";
                  GF_VIEWERS_CAN_EDIT.value = "false";
                  GF_EDITORS_CAN_ADMIN.value = "false";
                  GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH.value = "/var/lib/grafana/dashboards/cluster-overview.json";
                  GF_SECURITY_COOKIE_SECURE.value = "false";
                  GF_SECURITY_CONTENT_SECURITY_POLICY.value = "true";
                  GF_SECURITY_STRICT_TRANSPORT_SECURITY.value = "false";
                  GF_ALERTING_ENABLED.value = "true";
                  GF_UNIFIED_ALERTING_ENABLED.value = "true";
                  # Casdoor SSO via Generic OAuth
                  GF_AUTH_GENERIC_OAUTH_ENABLED.value = "true";
                  GF_AUTH_GENERIC_OAUTH_NAME.value = "Casdoor";
                  GF_AUTH_GENERIC_OAUTH_CLIENT_ID.value = "fa39ccce16fbc8ad4d23";
                  GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET.valueFrom.secretKeyRef = {
                    name = "grafana-oidc-secret";
                    key = "client-secret";
                  };
                  GF_AUTH_GENERIC_OAUTH_AUTH_URL.value = "https://auth.lan/login/oauth/authorize";
                  GF_AUTH_GENERIC_OAUTH_TOKEN_URL.value = "https://auth.lan/api/login/oauth/access_token";
                  GF_AUTH_GENERIC_OAUTH_API_URL.value = "https://auth.lan/api/userinfo";
                  GF_AUTH_GENERIC_OAUTH_SCOPES.value = "openid profile email";
                  GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP.value = "true";
                  GF_AUTH_GENERIC_OAUTH_EMAIL_ATTRIBUTE_NAME.value = "email";
                  GF_AUTH_GENERIC_OAUTH_NAME_ATTRIBUTE_PATH.value = "displayName";
                  GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH.value = "name";
                  GF_AUTH_SIGNOUT_REDIRECT_URL.value = "https://auth.lan/login/oauth/logout";
                };
                ports = [
                  {
                    containerPort = 3000;
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
                livenessProbe = httpProbe 3000 "/api/health";
                readinessProbe = httpProbe 3000 "/api/health";
                securityContext = containerSecurity;
                volumeMounts = {
                  _namedlist = true;
                  datasources = {
                    mountPath = "/etc/grafana/provisioning/datasources";
                    readOnly = true;
                  };
                  dashboards-provider = {
                    mountPath = "/etc/grafana/provisioning/dashboards";
                    readOnly = true;
                  };
                  dashboards = {
                    mountPath = "/var/lib/grafana/dashboards";
                    readOnly = true;
                  };
                  data = {
                    mountPath = "/var/lib/grafana";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              datasources.configMap.name = "grafana-datasources";
              dashboards-provider.configMap.name = "grafana-dashboards-provider";
              dashboards.configMap.name = "grafana-dashboards";
              data.emptyDir = {};
            };
          };
        };
      };
    };

    monitoring.PersistentVolumeClaim.grafana-data = {
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = storageClass;
        resources.requests.storage = "10Gi";
      };
    };

    monitoring.Service.grafana = {
      metadata.labels = managed // {app = "grafana";};
      spec = {
        type = "NodePort";
        ports = [
          {
            name = "http";
            port = 3000;
            targetPort = 3000;
            nodePort = 32102;
            protocol = "TCP";
          }
        ];
        selector.app = "grafana";
      };
    };

    # ── Alloy (DaemonSet — one per node) ───────────────────────
    monitoring.ConfigMap.alloy-config.data."config.alloy" = alloyConfig;

    monitoring.DaemonSet.alloy = {
      metadata.labels = managed // {app = "alloy";};
      spec = {
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "alloy";
        template = {
          metadata.labels = managed // {app = "alloy";};
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
    # ── Prometheus (scrapes targets, remote_writes to Mimir) ───
    monitoring.ConfigMap.prometheus-config.data."prometheus.yml" = prometheusConfig;

    monitoring.Deployment.prometheus = {
      metadata.labels = managed // {app = "prometheus";};
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
                livenessProbe = httpProbe 9090 "/-/healthy";
                readinessProbe = httpProbe 9090 "/-/ready";
                securityContext = containerSecurity;
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
      metadata.labels = managed // {app = "prometheus";};
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

    # ── AlertManager ───────────────────────────────────────
    monitoring.ConfigMap.alertmanager-config = {
      metadata.labels = managed // {app = "alertmanager";};
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
      metadata.labels = managed // {app = "alertmanager";};
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
            nodeSelector = sentrySelector;
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
      metadata.labels = managed // {app = "alertmanager";};
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
      metadata.labels = managed // {app = "alert-webhook";};
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
      metadata.labels = managed // {app = "alert-webhook";};
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
      metadata.labels = managed // {app = "kube-state-metrics";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "kube-state-metrics";
        template = {
          metadata.labels = managed // {app = "kube-state-metrics";};
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
      metadata.labels = managed // {app = "kube-state-metrics";};
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

    # ── PDBs ───────────────────────────────────────────────────
    monitoring.PodDisruptionBudget.loki-pdb = {
      spec.maxUnavailable = 1;
      spec.selector.matchLabels.app = "loki";
    };
    monitoring.PodDisruptionBudget.mimir-pdb = {
      spec.maxUnavailable = 1;
      spec.selector.matchLabels.app = "mimir";
    };
    monitoring.PodDisruptionBudget.grafana-pdb = {
      spec.maxUnavailable = 1;
      spec.selector.matchLabels.app = "grafana";
    };

    # =======================================================================
    # -- UNIQUE RESOURCES FROM YAML MANIFESTS (Phase 2 migration) ---------
    # =======================================================================

    # -- Alert Rules: API Server Health (ConfigMap) -----------------------
    # Source: api-server-alerts.yaml
    monitoring.ConfigMap.prometheus-api-server-rules.data."api-server-alerts.yml" = ''
      groups:
      - name: api-server-health
        interval: 30s
        rules:
      - alert: APIServerDown
        expr: up{job="kube-apiserver"} == 0
        for: 1m
        labels:
          severity: critical
          component: control-plane
        annotations:
          summary: "API server is down on {{ $labels.instance }}"
          description: "API server has been down for more than 1 minute"

      - alert: APIServerHighErrorRate
        expr: |
          sum(rate(apiserver_request_total{job="kube-apiserver",code=~"5.."}[5m]))
          /
          sum(rate(apiserver_request_total{job="kube-apiserver"}[5m])) > 0.05
        for: 5m
        labels:
          severity: warning
          component: control-plane
        annotations:
          summary: "API server returning high error rate (5%+)"

      - alert: APIServerHighLatency
        expr: |
          histogram_quantile(0.99,
            sum(rate(apiserver_request_latencies_seconds_bucket{job="kube-apiserver"}[5m])) by (le)
          ) > 1
        for: 10m
        labels:
          severity: warning
          component: control-plane
        annotations:
          summary: "API server p99 latency exceeds 1 second"

      - alert: EtcdHighRequestDuration
        expr: |
          histogram_quantile(0.99,
            sum(rate(etcd_request_duration_seconds_bucket[5m])) by (le)
          ) > 0.5
        for: 10m
        labels:
          severity: warning
          component: control-plane
        annotations:
          summary: "etcd requests experiencing high latency"

      - alert: APIServerRestart
        expr: |
          time() - process_start_time_seconds{job="kube-apiserver"} < 300
        for: 0m
        labels:
          severity: critical
          component: control-plane
        annotations:
          summary: "API server restarted on {{ $labels.instance }}"
          description: "API server restarted less than 5 minutes ago"

      - alert: APIServerPodCountMismatch
        expr: |
          count(up{job="kube-apiserver"}) != 3
        for: 5m
        labels:
          severity: critical
          component: control-plane
        annotations:
          summary: "Expected 3 API server pods, found {{ $value }}"

      - alert: ControlPlaneHighRestartRate
        expr: |
          increase(kube_pod_container_status_restarts_total{namespace="kube-system"}[1h]) > 5
        for: 5m
        labels:
          severity: warning
          component: control-plane
        annotations:
          summary: "Control plane pod restarting frequently"

      - name: api-server-capacity
        interval: 1m
        rules:
      - alert: APIServerHighCPU
        expr: |
          sum(rate(container_cpu_usage_seconds_total{namespace="kube-system",container=~"kube-apiserver|etcd"}[5m]))
          /
          sum(machine_cpu_cores)
          > 0.5
        for: 10m
        labels:
          severity: warning
          component: control-plane
        annotations:
          summary: "Control plane using >50% of cluster CPU"

      - alert: APIServerHighMemory
        expr: |
          sum(container_memory_working_set_bytes{namespace="kube-system",container=~"kube-apiserver|etcd"})
          /
          sum(machine_memory_bytes)
          > 0.2
        for: 10m
        labels:
          severity: warning
          component: control-plane
        annotations:
          summary: "Control plane using >20% of cluster memory"
    '';

    # -- Alert Rules: Kube API Server (ConfigMap version) -----------------
    # Source: prometheus-alert-rules-kube-apiserver.yaml
    monitoring.ConfigMap.prometheus-alert-rules-kube-apiserver.data."kube-apiserver-rules.yml" = ''
      groups:
        - name: kube-apiserver
          interval: 30s
          rules:
          - alert: KubeAPIServerDown
            expr: up{job="kube-apiserver-static"} == 0
            for: 1m
            labels:
              severity: critical
              component: control-plane
            annotations:
              summary: "Kubernetes API server is down"
              description: "Kubernetes API server on {{ $labels.instance }} has been down for more than 1 minute."

          - alert: KubeAPIServerRestarted
            expr: |
              time() - process_start_time_seconds{job="kube-apiserver-static"} < 300
            for: 0m
            labels:
              severity: warning
              component: control-plane
            annotations:
              summary: "Kubernetes API server restarted"

          - alert: KubeAPIServerLatencyHigh
            expr: |
              histogram_quantile(0.99, sum(rate(apiserver_request_duration_seconds_bucket{job="kube-apiserver-static"}[5m])) by (le, verb)) > 1
            for: 10m
            labels:
              severity: warning
              component: control-plane
            annotations:
              summary: "Kubernetes API server 99th percentile latency high"

          - alert: KubeAPIServerErrorsHigh
            expr: |
              sum(rate(apiserver_request_total{job="kube-apiserver-static",code=~"5.."}[5m]))
              /
              sum(rate(apiserver_request_total{job="kube-apiserver-static"}[5m])) > 0.05
            for: 10m
            labels:
              severity: warning
              component: control-plane
            annotations:
              summary: "Kubernetes API server error rate high"

          - alert: KubeAPIServerEtcdLatencyHigh
            expr: |
              histogram_quantile(0.99, sum(rate(apiserver_storage_db_request_duration_seconds_bucket{job="kube-apiserver-static"}[5m])) by (le, operation_name)) > 0.5
            for: 10m
            labels:
              severity: warning
              component: control-plane
            annotations:
              summary: "Kubernetes API server etcd latency high"
    '';

    # -- Alert Rules: Cluster Health (pod count, etcd size, evictions) ------
    monitoring.ConfigMap.prometheus-cluster-health-rules.data."cluster-health.yml" = ''
      groups:
      - name: cluster-pod-health
        interval: 30s
        rules:
        - alert: TooManyPodsInNamespace
          expr: |
            count by (namespace) (kube_pod_info) > 100
          for: 5m
          labels:
            severity: warning
            component: scheduling
          annotations:
            summary: "Namespace {{ $labels.namespace }} has {{ $value }} pods (>100)"
            description: "High pod count may indicate a leak or missing cleanup"

        - alert: EvictedPodsDetected
          expr: |
            sum by (namespace) (kube_pod_status_phase{phase="Failed",reason="Evicted"}) > 5
          for: 5m
          labels:
            severity: warning
            component: scheduling
          annotations:
            summary: "{{ $value }} evicted pods in namespace {{ $labels.namespace }}"
            description: "Pods are being evicted, possible resource pressure"

        - alert: CrashLoopingPods
          expr: |
            sum by (namespace) (kube_pod_container_status_restarts_total - kube_pod_container_status_restarts_total offset 5m) > 5
          for: 5m
          labels:
            severity: warning
            component: workloads
          annotations:
            summary: "Pods restarting frequently in {{ $labels.namespace }}"

      - name: etcd-health
        interval: 30s
        rules:
        - alert: EtcdClusterSizeMismatch
          expr: |
            count(etcd_server_has_leader) != 3
          for: 5m
          labels:
            severity: critical
            component: control-plane
          annotations:
            summary: "etcd cluster size mismatch: {{ $value }} members (expected 3)"

        - alert: EtcdNoLeader
          expr: |
            etcd_server_has_leader == 0
          for: 1m
          labels:
            severity: critical
            component: control-plane
          annotations:
            summary: "etcd member {{ $labels.instance }} has no leader"

        - alert: EtcdHighDBSize
          expr: |
            etcd_mvcc_db_total_size_in_bytes > 2147483648
          for: 10m
          labels:
            severity: warning
            component: control-plane
          annotations:
            summary: "etcd DB size {{ $value | humanize }}B (>2GB) on {{ $labels.instance }}"
            description: "etcd database is growing large. Check compaction and defrag."

        - alert: NodeNotReady
          expr: |
            kube_node_status_condition{condition="Ready",status="true"} == 0
          for: 5m
          labels:
            severity: critical
            component: nodes
          annotations:
            summary: "Node {{ $labels.node }} is NotReady"

        - alert: NodeDiskPressure
          expr: |
            kube_node_status_condition{condition="DiskPressure",status="true"} == 1
          for: 5m
          labels:
            severity: warning
            component: nodes
          annotations:
            summary: "Node {{ $labels.node }} has disk pressure"

        - alert: NodeMemoryPressure
          expr: |
            kube_node_status_condition{condition="MemoryPressure",status="true"} == 1
          for: 5m
          labels:
            severity: warning
            component: nodes
          annotations:
            summary: "Node {{ $labels.node }} has memory pressure"
    '';

    # -- Memory Monitor (CronJob on zephyr) --------------------------------
    # Source: memory-monitor-configmap.yaml, memory-monitor-cronjob.yaml
    monitoring.ConfigMap.memory-monitor-script.data."check-memory.sh" = ''
      #!/bin/bash
      THRESHOLD=75
      CURRENT=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100)}')
      if [ $CURRENT -gt $THRESHOLD ]; then
        echo "WARNING: Zephyr memory usage is ''${CURRENT}%"
        echo "Consider moving workloads or scaling up"
        free -h
        echo "Top memory consumers:"
        ps aux --sort=-%mem | head -10
      fi
    '';

    monitoring.CronJob.memory-monitor = {
      metadata.labels = managed // {app = "memory-monitor";};
      spec = {
        schedule = "*/5 * * * *";
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 1;
        jobTemplate.spec.template = {
          spec = {
            nodeName = "sentry";
            restartPolicy = "OnFailure";
            containers = {
              _namedlist = true;
              memory-check = {
                image = "docker.io/library/busybox:1.36";
                command = [
                  "/bin/sh"
                  "/scripts/check-memory.sh"
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "200m";
                    memory = "256Mi";
                  };
                };
                volumeMounts = {
                  _namedlist = true;
                  scripts = {
                    mountPath = "/scripts";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              scripts = {
                configMap = {
                  name = "memory-monitor-script";
                  defaultMode = 493;
                };
              };
            };
          };
        };
      };
    };

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
            to = [{namespaceSelector.matchLabels.name = "kube-system";}];
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
        managed
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
      metadata.labels = managed // {name = "prometheus-adapter";};
      spec = {
        replicas = 1;
        selector.matchLabels.name = "prometheus-adapter";
        template = {
          metadata.labels = managed // {name = "prometheus-adapter";};
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
      metadata.labels = managed // {name = "prometheus-adapter";};
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
    # === HA Infrastructure ===

    # CoreDNS HA enforcer: k3s resets CoreDNS to 1 replica on server restart.
    # This CronJob ensures 2 replicas every 5 minutes.
    kube-system.ServiceAccount.coredns-ha-enforcer = {};
    kube-system.Role.coredns-ha-enforcer.rules = [
      {
        apiGroups = ["apps"];
        resources = ["deployments"];
        resourceNames = ["coredns"];
        verbs = ["get" "patch"];
      }
    ];
    kube-system.RoleBinding.coredns-ha-enforcer = {
      subjects = [
        {
          kind = "ServiceAccount";
          name = "coredns-ha-enforcer";
        }
      ];
      roleRef = {
        kind = "Role";
        name = "coredns-ha-enforcer";
        apiGroup = "rbac.authorization.k8s.io";
      };
    };
    kube-system.CronJob.coredns-ha-enforcer = {
      schedule = "*/5 * * * *";
      concurrencyPolicy = "Forbid";
      successfulJobsHistoryLimit = 1;
      failedJobsHistoryLimit = 1;
      jobTemplate.spec.template.spec = {
        serviceAccountName = "coredns-ha-enforcer";
        restartPolicy = "OnFailure";
        containers = [
          {
            name = "enforcer";
            image = "bitnami/kubectl:1.35.4";
            command = ["bash" "-c" (builtins.readFile ./coredns-ha-enforcer.sh)];
            resources = {
              requests = {
                cpu = "10m";
                memory = "32Mi";
              };
              limits = {
                cpu = "50m";
                memory = "64Mi";
              };
            };
          }
        ];
      };
    };

    # Local container registry on nexus for cluster-built images.
    # Gateway HA pods on sentry pull from here instead of needing pre-loaded images.
    kube-system.PersistentVolumeClaim.local-registry-data = {
      accessModes = ["ReadWriteOnce"];
      storageClassName = "local-path";
      resources.requests.storage = "20Gi";
    };
    kube-system.Deployment.local-registry = {
      replicas = 1;
      selector.matchLabels.app = "local-registry";
      template.metadata.labels.app = "local-registry";
      template.spec = {
        nodeSelector."kubernetes.io/hostname" = "nexus";
        containers = [
          {
            name = "registry";
            image = "registry:2";
            ports = [
              {
                containerPort = 5000;
                hostPort = 5000;
                protocol = "TCP";
              }
            ];
            env.REGISTRY_STORAGE_DELETE_ENABLED = "true";
            volumeMounts = [
              {
                name = "data";
                mountPath = "/var/lib/registry";
              }
            ];
            livenessProbe = {
              httpGet = {
                path = "/v2/";
                port = 5000;
              };
              initialDelaySeconds = 5;
              periodSeconds = 10;
            };
            readinessProbe = {
              httpGet = {
                path = "/v2/";
                port = 5000;
              };
              initialDelaySeconds = 3;
              periodSeconds = 5;
            };
            resources = {
              requests = {
                cpu = "50m";
                memory = "64Mi";
              };
              limits = {
                cpu = "200m";
                memory = "256Mi";
              };
            };
          }
        ];
        volumes = [
          {
            name = "data";
            persistentVolumeClaim.claimName = "local-registry-data";
          }
        ];
      };
    };
    monitoring.NetworkPolicy.allow-monitoring-api-server = {
      spec = {
        podSelector.matchLabels.app = "alloy";
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{ipBlock.cidr = cluster.subnet;}];
            ports = [
              {
                protocol = "TCP";
                port = 6443;
              }
            ];
          }
        ];
      };
    };
  };
}
