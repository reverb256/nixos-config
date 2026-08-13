{
  monitoring,
  cluster,
  ...
}: {
  config.kubernetes.objects = {
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
            command = ["bash" "-c" (builtins.readFile ../coredns-ha-enforcer.sh)];
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
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "local-path";
        resources.requests.storage = "20Gi";
      };
    };
    kube-system.Deployment.local-registry = {
      spec = {
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
              env = [
                {
                  name = "REGISTRY_STORAGE_DELETE_ENABLED";
                  value = "true";
                }
              ];
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

    # ── Alerting rules for cluster failure modes ─────────────────────
    # These alerts would have caught the forge/sentry NFS-wedge, VIP
    # Previous monitoring incidents documented in hey.md.
    monitoring.PrometheusRule.cluster-alerts = {
      spec = {
        groups = [
          {
            name = "cluster-infra";
            interval = "30s";
            rules = [
              {
                alert = "KubeNodeNotReady";
                expr = "kube_node_status_condition{condition=\"Ready\",status=\"true\"} == 0";
                for = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "Kubernetes node {{ $labels.node }} is NotReady";
                  description = "Node {{ $labels.node }} has been NotReady for >2m. Check k3s/systemd.";
                };
              }
              {
                alert = "VIPMissing";
                expr = "node_netstat_Ip_Forwarding unless on(instance) (node_network_carrier{device=~\"eth0|eno1\"} == 1)";
                for = "3m";
                labels.severity = "critical";
                annotations = {
                  summary = "Keepalived VIP {{ $labels.vip }} is not hosted";
                  description = "No node holds the VIP 10.1.1.100. Keepalived may be down or health-check failing.";
                };
              }
              {
                alert = "KubeApiServerDown";
                expr = "absent(up{job=\"apiserver\"} == 1)";
                for = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "Kubernetes API server unreachable";
                  description = "The prometheus scrape of the apiserver has been absent for >2m — cluster control plane may be down.";
                };
              }
              {
                alert = "HighPodRestartRate";
                expr = "rate(kube_pod_container_status_restarts_total[15m]) > 0.5";
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Pod {{ $labels.namespace }}/{{ $labels.pod }} restarting frequently";
                  description = "Container {{ $labels.container }} in {{ $labels.namespace }}/{{ $labels.pod }} has restarted >0.5 times/min for 5m.";
                };
              }
              {
                alert = "UnboundDown";
                expr = "absent(node_systemd_unit_state{name=\"unbound.service\",state=\"active\"} == 1)";
                for = "3m";
                labels.severity = "critical";
                annotations = {
                  summary = "Unbound DNS service is not active on {{ $labels.instance }}";
                  description = "unbound.service is absent from active systemd units — cluster DNS resolution will fail.";
                };
              }
              {
                alert = "NFSMountStale";
                expr = "node_filesystem_device_error{device=~\".*nfs.*\"} == 1";
                for = "2m";
                labels.severity = "warning";
                annotations = {
                  summary = "NFS mount error on {{ $labels.instance }}";
                  description = "NFS mount {{ $labels.mountpoint }} on {{ $labels.instance }} is in error state (stale/server down).";
                };
              }
            ];
          }
          # Add here: blackbox-probe rules when blackbox-exporter is deployed
        ];
      };
    };
  };
}
