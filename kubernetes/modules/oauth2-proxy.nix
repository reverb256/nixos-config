{cluster, ...}: let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  namespace = "auth";
  # Import shared oauth2-proxy config (SSOT for all oauth2-proxy settings)
  oauth2Cfg = import ../../modules/services/oauth2-proxy-config.nix;
in {
  config.kubernetes.objects = {
    auth.ServiceAccount.oauth2-proxy = {
      automountServiceAccountToken = false;
    };

    # Secret managed imperatively: kubectl create secret generic oauth2-proxy-secrets ...
    # DO NOT define here — kubectl apply would overwrite real values with placeholders

    auth.Service.oauth2-proxy = {
      metadata.labels =
        managed
        // {
          app = "oauth2-proxy";
          "app.kubernetes.io/component" = "auth-proxy";
        };
      spec = {
        selector.app = "oauth2-proxy";
        type = "NodePort";
        ports._namedlist = true;
        ports.http = {
          port = 4180;
          targetPort = 4180;
          protocol = "TCP";
          nodePort = 30890;
        };
      };
    };

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
            nodeSelector."kubernetes.io/hostname" = "nexus";
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
              args = [
                "--provider=oidc"
                "--oidc-issuer-url=${oauth2Cfg.oidcIssuerUrl}"
                "--client-id=${oauth2Cfg.clientId}"
                "--client-secret-file=/etc/oauth2/secrets/client-secret"
                "--cookie-secret-file=/etc/oauth2/secrets/cookie-secret"
                "--http-address=0.0.0.0:4180"
                "--redirect-url=${oauth2Cfg.redirectUrl}"
                "--cookie-domain=${oauth2Cfg.cookieDomain}"
                "--cookie-secure=true"
                "--cookie-samesite=lax"
                "--cookie-httponly=true"
                "--email-domain=*"
                "--scope=${oauth2Cfg.scope}"
                "--ssl-insecure-skip-verify=true"
                "--reverse-proxy=true"
                "--set-xauthrequest=true"
                "--set-authorization-header=true"
                "--skip-provider-button=false"
                "--pass-access-token=true"
                "--pass-user-headers=true"
                "--skip-auth-route=${builtins.concatStringsSep "," oauth2Cfg.skipAuthRoutes}"
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
            };
            volumes._namedlist = true;
            volumes.secrets.secret.secretName = "oauth2-proxy-secrets";
          };
        };
      };
    };
  };
}
