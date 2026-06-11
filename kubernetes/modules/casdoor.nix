{cluster, ...}: let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  namespace = "auth";
in {
  config.kubernetes.objects = {
    none.Namespace.${namespace} = {
      metadata.labels =
        managed
        // {
          name = namespace;
          "pod-security.kubernetes.io/enforce" = "baseline";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        };
    };

    auth.ConfigMap.casdoor-postgres-config = {
      metadata.labels = managed // {app = "casdoor-postgres";};
      data.POSTGRES_DB = "casdoor";
      data.POSTGRES_USER = "casdoor";
    };

    # Secret managed imperatively: kubectl create secret generic casdoor-postgres-secret ...
    # DO NOT define here — kubectl apply would overwrite real values with placeholders

    auth.ConfigMap.casdoor-config = {
      metadata.labels = managed // {app = "casdoor";};
      data."app.conf.template" = ''
        appname = casdoor
        httpport = 8000
        runmode = prod
        copyrequestbody = true
        driverName = postgres
        dataSourceName = user=casdoor host=casdoor-postgres.${namespace}.svc.cluster.local port=5432 sslmode=disable dbname=casdoor password=POSTGRES_PASSWORD_PLACEHOLDER
        dbName = casdoor
        tableNamePrefix =
        showSql = false
        redisEndpoint =
        defaultStorageProvider =
        isCloudIntranet = false
        authState = "casdoor"
        verificationCodeTimeout = 10
        initScore = 0
        logPostOnly = true
        isUsernameLowered = false
        origin = https://auth.lan
        staticBaseUrl = "https://cdn.casbin.org"
        isDemoMode = false
        batchSize = 100
        showGithubCorner = false
        defaultLanguage = "en"
        defaultApplication = "app-built-in"
        maxItemsForFlatMenu = 7
        enableGzip = true
        initDataNewOnly = false
        initDataFile = "./init_data.json"
      '';
    };

    auth.ServiceAccount.casdoor = {
      automountServiceAccountToken = false;
    };

    auth.StatefulSet.casdoor-postgres = {
      metadata.labels =
        managed
        // {
          app = "casdoor-postgres";
          "app.kubernetes.io/component" = "database";
        };
      spec = {
        serviceName = "casdoor-postgres";
        replicas = 1;
        selector.matchLabels.app = "casdoor-postgres";
        template = {
          metadata.labels =
            managed
            // {
              app = "casdoor-postgres";
              "app.kubernetes.io/component" = "database";
            };
          spec = {
            nodeSelector."kubernetes.io/hostname" = "nexus";
            securityContext = {
              fsGroup = 999;
              runAsUser = 999;
              runAsGroup = 999;
              runAsNonRoot = true;
              seccompProfile.type = "RuntimeDefault";
            };
            containers._namedlist = true;
            containers.postgres = {
              image = "postgres:18.3-alpine";
              imagePullPolicy = "IfNotPresent";
              ports._namedlist = true;
              ports.postgresql = {
                containerPort = 5432;
                protocol = "TCP";
              };
              env._namedlist = true;
              env = {
                POSTGRES_DB.valueFrom.configMapKeyRef = {
                  name = "casdoor-postgres-config";
                  key = "POSTGRES_DB";
                };
                POSTGRES_USER.valueFrom.configMapKeyRef = {
                  name = "casdoor-postgres-config";
                  key = "POSTGRES_USER";
                };
                POSTGRES_PASSWORD.valueFrom.secretKeyRef = {
                  name = "casdoor-postgres-secret";
                  key = "POSTGRES_PASSWORD";
                };
                PGDATA.value = "/var/lib/postgresql/data/pgdata";
              };
              resources = {
                requests = {
                  cpu = "250m";
                  memory = "256Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "512Mi";
                };
              };
              livenessProbe = {
                exec.command = ["pg_isready" "-U" "casdoor" "-d" "casdoor"];
                initialDelaySeconds = 20;
                periodSeconds = 10;
                timeoutSeconds = 5;
                failureThreshold = 6;
              };
            };
          };
        };
        volumeClaimTemplates = [
          {
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              storageClassName = "local-path";
              resources.requests.storage = "2Gi";
            };
          }
        ];
      };
    };

    auth.Service.casdoor-postgres = {
      metadata.labels =
        managed
        // {
          app = "casdoor-postgres";
          "app.kubernetes.io/component" = "database";
        };
      spec = {
        type = "ClusterIP";
        selector.app = "casdoor-postgres";
        ports._namedlist = true;
        ports.postgresql = {
          port = 5432;
          targetPort = 5432;
          protocol = "TCP";
        };
      };
    };

    auth.Deployment.casdoor = {
      metadata.labels =
        managed
        // {
          app = "casdoor";
          "app.kubernetes.io/component" = "api";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "casdoor";
        template = {
          metadata.labels =
            managed
            // {
              app = "casdoor";
              "app.kubernetes.io/component" = "api";
            };
          spec = {
            nodeSelector."kubernetes.io/hostname" = "nexus";
            serviceAccountName = "casdoor";
            securityContext = {
              seccompProfile.type = "RuntimeDefault";
            };
            initContainers._namedlist = true;
            initContainers.setup-config = {
              image = "alpine:3.19";
              command = ["sh" "-c" "sed \"s/POSTGRES_PASSWORD_PLACEHOLDER/$POSTGRES_PASSWORD/g\" /template/app.conf.template > /config/app.conf"];
              env._namedlist = true;
              env.POSTGRES_PASSWORD.valueFrom.secretKeyRef = {
                name = "casdoor-postgres-secret";
                key = "POSTGRES_PASSWORD";
              };
              volumeMounts._namedlist = true;
              volumeMounts.template = {mountPath = "/template";};
              volumeMounts.config = {mountPath = "/config";};
            };
            containers._namedlist = true;
            containers.casdoor = {
              image = "docker.io/casbin/casdoor:3.49.0";
              imagePullPolicy = "IfNotPresent";
              env._namedlist = true;
              env.RUNNING_IN_DOCKER.value = "true";
              ports._namedlist = true;
              ports.http = {
                containerPort = 8000;
                protocol = "TCP";
              };
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "1Gi";
                };
              };
              startupProbe = {
                httpGet = {
                  path = "/";
                  port = 8000;
                };
                periodSeconds = 15;
                initialDelaySeconds = 30;
                failureThreshold = 10;
              };
              readinessProbe = {
                httpGet = {
                  path = "/";
                  port = 8000;
                };
                periodSeconds = 10;
                initialDelaySeconds = 10;
              };
              livenessProbe = {
                httpGet = {
                  path = "/";
                  port = 8000;
                };
                periodSeconds = 30;
                initialDelaySeconds = 30;
                failureThreshold = 3;
              };
              volumeMounts._namedlist = true;
              volumeMounts.config = {
                mountPath = "/conf/app.conf";
                subPath = "app.conf";
                readOnly = true;
              };
            };
            volumes._namedlist = true;
            volumes.template.configMap.name = "casdoor-config";
            volumes.config.emptyDir = {};
          };
        };
      };
    };

    auth.Service.casdoor = {
      metadata.labels = managed // {app = "casdoor";};
      spec = {
        type = "NodePort";
        selector.app = "casdoor";
        ports._namedlist = true;
        ports.http = {
          port = 8000;
          targetPort = 8000;
          nodePort = 32556;
          protocol = "TCP";
        };
      };
    };

    auth.NetworkPolicy.casdoor-ingress = {
      metadata.labels = managed;
      spec = {
        podSelector.matchLabels.app = "casdoor";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";}];
            ports = [
              {
                port = 8000;
                protocol = "TCP";
              }
            ];
          }
          {
            from = [{ipBlock.cidr = cluster.podCidr;}];
            ports = [
              {
                port = 8000;
                protocol = "TCP";
              }
            ];
          }
          {
            from = [{ipBlock.cidr = cluster.subnet;}];
            ports = [
              {
                port = 8000;
                protocol = "TCP";
              }
            ];
          }
        ];
      };
    };

    auth.NetworkPolicy.casdoor-egress = {
      metadata.labels = managed;
      spec = {
        podSelector.matchLabels.app = "casdoor";
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";}];
            ports = [
              {
                port = 53;
                protocol = "UDP";
              }
              {
                port = 53;
                protocol = "TCP";
              }
            ];
          }
          {
            to = [{podSelector.matchLabels.app = "casdoor-postgres";}];
            ports = [
              {
                port = 5432;
                protocol = "TCP";
              }
            ];
          }
        ];
      };
    };

    auth.NetworkPolicy.casdoor-postgres-egress = {
      metadata.labels = managed;
      spec = {
        podSelector.matchLabels.app = "casdoor-postgres";
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";}];
            ports = [
              {
                port = 53;
                protocol = "UDP";
              }
              {
                port = 53;
                protocol = "TCP";
              }
            ];
          }
        ];
      };
    };
    # NOTE: No default-deny-all in auth namespace.
    # kube-router iptables ordering can cause blanket DROP to override
    # podSelector-based egress rules (casdoor->postgres conn refused).
    # All auth pods already have fine-grained policies.
  };
}
