{cluster, ...}: let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  namespace = "auth";
in {
  config.kubernetes.objects = {
    auth.ServiceAccount.oauth2-proxy = {
      automountServiceAccountToken = false;
    };

    # Secret managed imperatively: kubectl create secret generic oauth2-proxy-secrets ...
    # DO NOT define here — kubectl apply would overwrite real values with placeholders

    auth.Deployment.oauth2-proxy = {
      metadata.labels =
        managed
        // {
          app = "oauth2-proxy";
          "app.kubernetes.io/component" = "auth-proxy";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "oauth2-proxy";
        template = {
          metadata.labels =
            managed
            // {
              app = "oauth2-proxy";
              "app.kubernetes.io/component" = "auth-proxy";
            };
          spec = {
            nodeSelector."kubernetes.io/hostname" = "zephyr";
            serviceAccountName = "oauth2-proxy";
            securityContext = {
              runAsNonRoot = true;
              seccompProfile.type = "RuntimeDefault";
            };
            containers._namedlist = true;
            containers.oauth2-proxy = {
              image = "quay.io/oauth2-proxy/oauth2-proxy:v7.15.2";
              imagePullPolicy = "IfNotPresent";
              ports._namedlist = true;
              ports.http = {
                containerPort = 4180;
                protocol = "TCP";
              };
              env._namedlist = true;
              env.SSL_CERT_FILE.value = "/etc/ssl/cluster-ca/ca.crt";
              args = [
                "--provider=oidc"
                "--oidc-issuer-url=https://auth.lan"
                "--client-id=5bf72a094f75c6f5729e"
                "--client-secret-file=/etc/oauth2/secrets/client-secret"
                "--cookie-secret-file=/etc/oauth2/secrets/cookie-secret"
                "--http-address=0.0.0.0:4180"
                "--redirect-url=https://auth.lan/oauth2/callback"
                "--cookie-domain=.lan"
                "--cookie-secure=true"
                "--cookie-samesite=lax"
                "--cookie-httponly=true"
                "--email-domain=*"
                "--scope=openid profile email"
                "--ssl-insecure-skip-verify=true"
                "--reverse-proxy=true"
                "--set-xauthrequest=true"
                "--set-authorization-header=true"
                "--skip-provider-button=false"
                "--pass-access-token=true"
                "--pass-user-headers=true"
                "--skip-auth-route=^/health$,^/healthz$,^/api/health$,^/ready$,^/metrics$,^/favicon$,^/assets/,^/public/,^/static/"
                "--whitelist-domain=.lan"
                "--insecure-oidc-allow-unverified-email=true"
                "--insecure-oidc-skip-issuer-verification=true"
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "128Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "256Mi";
                };
              };
              livenessProbe = {
                httpGet = {
                  path = "/ping";
                  port = 4180;
                };
                initialDelaySeconds = 10;
                periodSeconds = 30;
                failureThreshold = 3;
              };
              readinessProbe = {
                httpGet = {
                  path = "/ping";
                  port = 4180;
                };
                initialDelaySeconds = 5;
                periodSeconds = 10;
                failureThreshold = 3;
              };
              volumeMounts._namedlist = true;
              volumeMounts.secrets = {
                mountPath = "/etc/oauth2/secrets";
                readOnly = true;
              };
              volumeMounts.ca-cert = {
                mountPath = "/etc/ssl/cluster-ca";
                readOnly = true;
              };
            };
            volumes._namedlist = true;
            volumes.secrets.secret.secretName = "oauth2-proxy-secrets";
            volumes.ca-cert.hostPath = {
              path = "/etc/ssl/cluster-ca";
              type = "Directory";
            };
          };
        };
      };
    };

    auth.Service.oauth2-proxy = {
      metadata.labels =
        managed
        // {
          app = "oauth2-proxy";
          "app.kubernetes.io/component" = "auth-proxy";
        };
      spec = {
        type = "ClusterIP";
        selector.app = "oauth2-proxy";
        ports._namedlist = true;
        ports.http = {
          port = 4180;
          targetPort = 4180;
          protocol = "TCP";
        };
      };
    };

    auth.NetworkPolicy.oauth2-proxy-ingress = {
      metadata.labels = managed;
      spec = {
        podSelector.matchLabels.app = "oauth2-proxy";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{ipBlock.cidr = cluster.podCidr;}];
            ports = [
              {
                port = 4180;
                protocol = "TCP";
              }
            ];
          }
          {
            from = [{ipBlock.cidr = cluster.subnet;}];
            ports = [
              {
                port = 4180;
                protocol = "TCP";
              }
            ];
          }
        ];
      };
    };

    auth.NetworkPolicy.oauth2-proxy-egress = {
      metadata.labels = managed;
      spec = {
        podSelector.matchLabels.app = "oauth2-proxy";
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{namespaceSelector.matchLabels.name = "kube-system";}];
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
            to = [{podSelector.matchLabels.app = "casdoor";}];
            ports = [
              {
                port = 8000;
                protocol = "TCP";
              }
            ];
          }
          {
            to = [{ipBlock.cidr = cluster.subnet;}];
            ports = [
              {
                port = 443;
                protocol = "TCP";
              }
            ];
          }
        ];
      };
    };
  };
}
