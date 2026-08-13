{
  monitoring,
  ...
}: {
  config.kubernetes.objects = {
    # ── Grafana admin secret ──────────────────────────────────
    # Populated by kubectl-apply-k8s-secrets from sops-nix:
    #   admin-password ← /run/secrets/grafana-admin-password
    # grafana-oidc-secret populated by kubectl-apply-k8s-secrets from sops-nix
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
      builtins.toJSON monitoring.grafanaDatasources;

    monitoring.Deployment.grafana = {
      metadata.labels = monitoring.managed // {app = "grafana";};
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
                image = monitoring.grafanaImage;
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
                livenessProbe = monitoring.httpProbe 3000 "/api/health";
                readinessProbe = monitoring.httpProbe 3000 "/api/health";
                securityContext = monitoring.containerSecurity;
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
        storageClassName = monitoring.storageClass;
        resources.requests.storage = "10Gi";
      };
    };

    monitoring.Service.grafana = {
      metadata.labels = monitoring.managed // {app = "grafana";};
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

    # ── PodDisruptionBudget ──
    monitoring.PodDisruptionBudget.grafana-pdb = {
      spec.maxUnavailable = 1;
      spec.selector.matchLabels.app = "grafana";
    };
  };
}
