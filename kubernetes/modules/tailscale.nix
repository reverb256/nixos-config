{pkgs, ...}: let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  # Template for a tailscale funnel ingress with HA proxy-group
  mkHAFunnelIngress = namespace: name: port: proxyGroup: {
    metadata = {
      inherit namespace;
      annotations = {
        "tailscale.com/funnel" = "true";
        "tailscale.com/proxy-group" = proxyGroup;
      };
      labels = managed // {app = "maplespike-${name}";};
    };
    spec = {
      ingressClassName = "tailscale";
      rules = [
        {
          http = {
            paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend = {
                  service = {
                    name = "maplespike-${name}";
                    port.number = port;
                  };
                };
              }
            ];
          };
        }
      ];
    };
  };

  # Template for a standard (non-HA) tailscale ingress
  mkIngress = namespace: name: port: {
    metadata = {
      inherit namespace;
      labels = managed // {app = name;};
    };
    spec = {
      ingressClassName = "tailscale";
      rules = [
        {
          http = {
            paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend = {
                  service = {
                    inherit name;
                    port.number = port;
                  };
                };
              }
            ];
          };
        }
      ];
    };
  };
in {
  config = {
    importyaml.tailscale-crds = {
      src = pkgs.runCommand "tailscale-crds.yaml" {} ''
        cp ${../../kubernetes-manifests/tailscale/crds.yaml} $out
      '';
    };

    kubernetes.objects = {
      # ── Tailscale Operator Namespace ─────────────────────────
      none.Namespace.tailscale-prod = {
        metadata.labels =
          managed
          // {
            name = "tailscale-prod";
            "pod-security.kubernetes.io/enforce" = "baseline";
            "pod-security.kubernetes.io/audit" = "restricted";
            "pod-security.kubernetes.io/warn" = "restricted";
          };
      };

      # ── Ingress Class ────────────────────────────────────────
      none.IngressClass.tailscale = {
        spec.controller = "tailscale.com/ts-ingress";
      };

      # ── ClusterRole (tailscale operator RBAC) ────────────────
      none.ClusterRole.tailscale-operator = {
        metadata.labels = managed;
        rules = [
          {
            apiGroups = [""];
            resources = ["nodes" "events" "services" "services/status"];
            verbs = ["get" "list" "watch" "create" "delete" "deletecollection" "patch" "update"];
          }
          {
            apiGroups = ["networking.k8s.io"];
            resources = ["ingresses" "ingresses/status" "ingressclasses"];
            verbs = ["get" "list" "watch" "create" "delete" "deletecollection" "patch" "update"];
          }
          {
            apiGroups = ["discovery.k8s.io"];
            resources = ["endpointslices"];
            verbs = ["get" "list" "watch"];
          }
          {
            apiGroups = ["tailscale.com"];
            resources = [
              "connectors"
              "connectors/status"
              "proxyclasses"
              "proxyclasses/status"
              "proxygroups"
              "proxygroups/status"
              "dnsconfigs"
              "dnsconfigs/status"
              "tailnets"
              "tailnets/status"
              "proxygrouppolicies"
              "proxygrouppolicies/status"
              "recorders"
              "recorders/status"
            ];
            verbs = ["get" "list" "watch" "update"];
          }
          {
            apiGroups = ["apiextensions.k8s.io"];
            resourceNames = ["servicemonitors.monitoring.coreos.com"];
            resources = ["customresourcedefinitions"];
            verbs = ["get" "list" "watch"];
          }
          {
            apiGroups = ["admissionregistration.k8s.io"];
            resources = ["validatingadmissionpolicies" "validatingadmissionpolicybindings"];
            verbs = ["list" "create" "delete" "update" "get" "watch"];
          }
        ];
      };

      # ── Operator Service Account ─────────────────────────────
      "tailscale-prod".ServiceAccount.operator = {
        metadata.labels = managed;
      };
      "tailscale-prod".ServiceAccount.proxies = {
        metadata.labels = managed;
      };

      # ── OAuth Secret (operator auth to Tailscale API) ────────
      "tailscale-prod".Secret.operator-oauth = {
        metadata.labels = managed;
        type = "Opaque";
        stringData = {
          # TODO: Fill from agenix key `tailscale-oauth` (see modules/system/agenix-secrets-registry.nix)
          client_id = "";
          client_secret = "";
        };
      };

      # ── ClusterRoleBinding ───────────────────────────────────
      none.ClusterRoleBinding.tailscale-operator = {
        metadata.labels = managed;
        subjects = [
          {
            kind = "ServiceAccount";
            name = "operator";
            namespace = "tailscale-prod";
          }
        ];
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "tailscale-operator";
        };
      };

      # ── RBAC Roles ──────────────────────────────────────────
      "tailscale-prod".Role.operator = {
        metadata.labels = managed;
        rules = [
          {
            apiGroups = [""];
            resources = ["secrets" "serviceaccounts" "configmaps"];
            verbs = ["create" "delete" "deletecollection" "get" "list" "patch" "update" "watch"];
          }
          {
            apiGroups = [""];
            resources = ["pods"];
            verbs = ["get" "list" "watch" "update"];
          }
          {
            apiGroups = [""];
            resources = ["pods/status"];
            verbs = ["update"];
          }
          {
            apiGroups = ["apps"];
            resources = ["statefulsets" "deployments"];
            verbs = ["create" "delete" "deletecollection" "get" "list" "patch" "update" "watch"];
          }
          {
            apiGroups = ["discovery.k8s.io"];
            resources = ["endpointslices"];
            verbs = ["get" "list" "watch" "create" "update" "deletecollection"];
          }
          {
            apiGroups = ["rbac.authorization.k8s.io"];
            resources = ["roles" "rolebindings"];
            verbs = ["get" "create" "patch" "update" "list" "watch" "deletecollection"];
          }
          {
            apiGroups = ["monitoring.coreos.com"];
            resources = ["servicemonitors"];
            verbs = ["get" "list" "update" "create" "delete"];
          }
        ];
      };

      "tailscale-prod".Role.proxies = {
        metadata.labels = managed;
        rules = [
          {
            apiGroups = [""];
            resources = ["secrets"];
            verbs = ["create" "delete" "deletecollection" "get" "list" "patch" "update" "watch"];
          }
          {
            apiGroups = [""];
            resources = ["events"];
            verbs = ["create" "patch" "get"];
          }
        ];
      };

      # ── RoleBindings ─────────────────────────────────────────
      "tailscale-prod".RoleBinding.operator = {
        metadata.labels = managed;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = "operator";
        };
        subjects = [
          {
            kind = "ServiceAccount";
            name = "operator";
            namespace = "tailscale-prod";
          }
        ];
      };

      "tailscale-prod".RoleBinding.proxies = {
        metadata.labels = managed;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = "proxies";
        };
        subjects = [
          {
            kind = "ServiceAccount";
            name = "proxies";
            namespace = "tailscale-prod";
          }
        ];
      };

      # ── Operator Deployment (main/unstable branch) ──────────
      "tailscale-prod".Deployment.operator = {
        metadata.labels = managed // {app = "operator";};
        spec = {
          replicas = 1;
          selector.matchLabels.app = "operator";
          strategy.type = "Recreate";
          template = {
            metadata.labels.app = "operator";
            spec = {
              nodeSelector."kubernetes.io/os" = "linux";
              serviceAccountName = "operator";
              containers = {
                _namedlist = true;
                operator = {
                  image = "tailscale/k8s-operator:v1.96.5";
                  imagePullPolicy = "Always";
                  name = "operator";
                  env = {
                    _namedlist = true;
                    OPERATOR_INITIAL_TAGS.value = "tag:k8s-operator";
                    OPERATOR_HOSTNAME.value = "tailscale-operator-prod";
                    OPERATOR_SECRET.value = "operator";
                    OPERATOR_LOGGING.value = "info";
                    OPERATOR_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                    OPERATOR_LOGIN_SERVER.value = "";
                    OPERATOR_INGRESS_CLASS_NAME.value = "tailscale";
                    CLIENT_ID_FILE.value = "/oauth/client_id";
                    CLIENT_SECRET_FILE.value = "/oauth/client_secret";
                    PROXY_IMAGE.value = "tailscale/tailscale:v1.96.5";
                    PROXY_TAGS.value = "tag:k8s";
                    APISERVER_PROXY.value = "false";
                    PROXY_FIREWALL_MODE.value = "auto";
                    POD_NAME.valueFrom.fieldRef.fieldPath = "metadata.name";
                    POD_UID.valueFrom.fieldRef.fieldPath = "metadata.uid";
                  };
                  volumeMounts = {
                    _namedlist = true;
                    oauth = {
                      mountPath = "/oauth";
                      readOnly = true;
                    };
                  };
                };
              };
              volumes = {
                _namedlist = true;
                oauth.secret.secretName = "operator-oauth";
              };
            };
          };
        };
      };

      # ── HA ProxyClass: prod ─────────────────────────────────
      none.ProxyClass.ha-funnel-prod = {
        metadata.labels = managed;
        spec = {
          metrics.enable = true;
          statefulSet.pod = {
            affinity = {
              podAntiAffinity = {
                preferredDuringSchedulingIgnoredDuringExecution = [
                  {
                    weight = 100;
                    podAffinityTerm = {
                      labelSelector.matchLabels.app = "funnel-proxies-prod";
                      topologyKey = "kubernetes.io/hostname";
                    };
                  }
                ];
              };
            };
            tailscaleContainer.resources = {
              limits = {
                cpu = "500m";
                memory = "128Mi";
              };
              requests = {
                cpu = "100m";
                memory = "64Mi";
              };
            };
            tolerations = [
              {
                key = "node.forge/mining";
                operator = "Exists";
                effect = "NoSchedule";
              }
            ];
          };
        };
      };

      # ── HA ProxyGroup: prod ─────────────────────────────────
      none.ProxyGroup.funnel-proxies-prod = {
        metadata = {
          labels = managed;
          namespace = "tailscale-prod";
        };
        spec = {
          type = "ingress";
          replicas = 2;
          proxyClass = "ha-funnel-prod";
        };
      };

      # ── HA ProxyClass: dev ──────────────────────────────────
      none.ProxyClass.ha-funnel-dev = {
        metadata.labels = managed;
        spec = {
          metrics.enable = true;
          statefulSet.pod = {
            affinity = {
              podAntiAffinity = {
                preferredDuringSchedulingIgnoredDuringExecution = [
                  {
                    weight = 100;
                    podAffinityTerm = {
                      labelSelector.matchLabels.app = "funnel-proxies-dev";
                      topologyKey = "kubernetes.io/hostname";
                    };
                  }
                ];
              };
            };
            tailscaleContainer.resources = {
              limits = {
                cpu = "500m";
                memory = "128Mi";
              };
              requests = {
                cpu = "100m";
                memory = "64Mi";
              };
            };
            tolerations = [
              {
                key = "node.forge/mining";
                operator = "Exists";
                effect = "NoSchedule";
              }
            ];
          };
        };
      };

      # ── HA ProxyGroup: dev ──────────────────────────────────
      none.ProxyGroup.funnel-proxies-dev = {
        metadata = {
          labels = managed;
          namespace = "tailscale-prod";
        };
        spec = {
          type = "ingress";
          replicas = 2;
          proxyClass = "ha-funnel-dev";
        };
      };

      # ── Prod HA Funnel Ingresses ────────────────────────────
      maplespike.Ingress.maplespike-api = mkHAFunnelIngress "maplespike" "api" 8082 "funnel-proxies-prod";
      maplespike.Ingress.maplespike-portal = mkHAFunnelIngress "maplespike" "portal" 8080 "funnel-proxies-prod";

      # ── Dev HA Funnel Ingresses ─────────────────────────────
      "maplespike-dev".Ingress.maplespike-api = mkHAFunnelIngress "maplespike-dev" "api" 8082 "funnel-proxies-dev";
      "maplespike-dev".Ingress.maplespike-portal = mkHAFunnelIngress "maplespike-dev" "portal" 8080 "funnel-proxies-dev";
      "maplespike-dev".Ingress.maplespike-mcp = mkHAFunnelIngress "maplespike-dev" "mcp" 3001 "funnel-proxies-dev";

      # ── Standard (non-HA) Ingresses ─────────────────────────
      maplespike.Ingress.maplespike-mcp = mkIngress "maplespike" "maplespike-mcp" 3001;
      maplespike.Ingress.uptime-kuma = mkIngress "maplespike" "uptime-kuma" 3001;
    };
  };
}
