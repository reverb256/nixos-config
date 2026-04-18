{ pkgs, config, lib, ... }:
{
  config.kubernetes.objects = {
    none.Namespace.search = {
      metadata.labels = {
        name = "search";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    search.Secret.searxng-secret = {
      type = "Opaque";
      stringData = {
        "secret-key" = "a3J5cHRleF82NHJhbmRvbXNlY3JldGtleTEyMw==";
      };
    };

    search.ConfigMap.searxng-config = {
      data."settings.yml" = ''
        server:
          port: 7777
          secret_key: "@SEARXNG_SECRET_KEY@"
          limiter: false
          image_proxy: true
        search:
          formats:
            - html
            - json
            - csv
            - rss
        ui:
          infinite_scroll: false
          static_use_hash: true
      '';
    };

    search.ConfigMap.searxng-settings-production = {
      data."settings.yml" = ''
        server:
          limiter: false
          secret_key: "@SEARXNG_SECRET_KEY@"
          methods: []
          port: 8888
          bind_address: "127.0.0.1"

        search:
          formats:
            - html
            - csv
            - json
            - rss
          language: en

        engines:
          - name: google
          - name: stackoverflow
          - name: github
      '';
    };

    # Migrated from searxng/02-settings-configmap.yaml
    # Full production settings with engine whitelist and limiter config
    search.ConfigMap.searxng-settings = {
      metadata.labels.app = "searxng";
      data = {
        "limiter.toml" = ''
          [botdetection.ip_limit]
          link_token = false
        '';
        "settings.yml" = ''
          use_default_settings: true

          # Completely remove engines that crash on init
          engines_drop:
            - wikidata

          server:
            limiter: false
            secret_key: "REDACTED_SEARXNG_SECRET_KEY"
            image_proxy: true
            method: "GET"
            port: 8080
            bind_address: "0.0.0.0"

          search:
            formats:
              - html
              - csv
              - json
              - rss
            language: en
            safe_search: 0

          outgoing:
            request_timeout: 10.0
            max_request_timeout: 15.0
            pool_connections: 100
            pool_maxsize: 50
            enable_http2: true
            retries: 2
            retry_on_http_error:
              - 403
              - 429
              - 500
              - 502
              - 503
              - 504

          # valkey:
          #   url: valkey://valkey.search.svc.cluster.local:6379/0

          engines:
            # -- General --
            - name: google
            - name: duckduckgo
            - name: bing
            - name: brave
            - name: startpage

            # -- IT --
            - name: github
            - name: stackoverflow
            - name: reddit
            - name: hackernews
            - name: mdn
            - name: gitlab
            - name: npm
            - name: pypi
            - name: docker hub
            - name: huggingface

            # -- Science --
            - name: google scholar
            - name: arxiv
            - name: pubmed
            - name: semantic scholar
            - name: wikipedia
            - name: wikidata
              disabled: true

            # -- News --
            - name: google news
            - name: bing news
            - name: duckduckgo news
            - name: reuters

            # -- Wikis --
            - name: nixos wiki

            # -- Explicitly disable noisy engines --
            - name: 1337x
              disabled: true
            - name: 9gag
              disabled: true
            - name: ahmia
              disabled: true
            - name: apple app store
              disabled: true
            - name: apple maps
              disabled: true
            - name: artic
              disabled: true
            - name: bandwidthcamp
              disabled: true
            - name: bilibili
              disabled: true
            - name: bing images
              disabled: true
            - name: bing videos
              disabled: true
            - name: bitchute
              disabled: true
            - name: bt4g
              disabled: true
            - name: currency
              disabled: true
            - name: dailymotion
              disabled: true
            - name: deezer
              disabled: true
            - name: deviantart
              disabled: true
            - name: digg
              disabled: true
            - name: duckduckgo images
              disabled: true
            - name: duckduckgo videos
              disabled: true
            - name: duckduckgo weather
              disabled: true
            - name: ebay
              disabled: true
            - name: flickr
              disabled: true
            - name: imgur
              disabled: true
            - name: invidious
              disabled: true
            - name: lemmy
              disabled: true
            - name: mastodon
              disabled: true
            - name: nyaa
              disabled: true
            - name: odysee
              disabled: true
            - name: peertube
              disabled: true
            - name: pinterest
              disabled: true
            - name: piped
              disabled: true
            - name: rumble
              disabled: true
            - name: soundcloud
              disabled: true
            - name: spotify
              disabled: true
            - name: steam
              disabled: true
            - name: vimeo
              disabled: true
            - name: wallhaven
              disabled: true
            - name: youtube
              disabled: true
            - name: youtube.music
              disabled: true
            - name: yummly
              disabled: true
            - name: zlibrary
              disabled: true
        '';
      };
    };

    # Migrated from search/03-deployment.yaml - updated production deployment
    search.Deployment.searxng = {
      metadata.labels.app = "searxng";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "searxng";
        strategy.type = "Recreate";
        template = {
          metadata.labels.app = "searxng";
          spec = {
            nodeName = "nexus";
            enableServiceLinks = false;
            automountServiceAccountToken = false;
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1001;
              runAsGroup = 1001;
              fsGroup = 1001;
              seccompProfile.type = "RuntimeDefault";
            };
            containers = {
              _namedlist = true;
              searxng = {
                image = "searxng/searxng:2024.7.0-480c5be7";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = [ "ALL" ];
                };
                env = {
                  _namedlist = true;
                  SEARXNG_SECRET.valueFrom.secretKeyRef = { name = "searxng-secret"; key = "secret-key"; };
                  SEARXNG_PORT.value = "8080";
                  SEARXNG_BASE_URL.value = "https://search.cluster.local/";
                  INSTANCE_NAME.value = "searxng-cluster";
                };
                ports = [
                  {
                    name = "http";
                    containerPort = 8080;
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    memory = "256Mi";
                    cpu = "200m";
                  };
                  limits = {
                    memory = "512Mi";
                    cpu = "1";
                  };
                };
                livenessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = "http";
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  timeoutSeconds = 10;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = "http";
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                volumeMounts = {
                  _namedlist = true;
                  settings = {
                    mountPath = "/etc/searxng/settings.yml";
                    subPath = "settings.yml";
                    readOnly = true;
                  };
                  data = {
                    mountPath = "/etc/searxng/data";
                  };
                };
              };
            };
            initContainers = {
              _namedlist = true;
              patch-settings = {
                image = "searxng/searxng:2024.7.0-480c5be7";
                command = ["/bin/sh" "-c" ''
                  cd /etc/searxng
                  sed -i 's/^    - html$/    - html\n    - csv\n    - json\n    - rss/' settings.yml
                  cat > limiter.toml << 'EOF'
                  [botdetection.ip_limit]
                  link_token = false
                  EOF
                ''];
                volumeMounts = {
                  _namedlist = true;
                  settings.mountPath = "/etc/searxng";
                };
              };
            };
            volumes = {
              _namedlist = true;
              settings.configMap.name = "searxng-settings";
              data.emptyDir = { };
            };
          };
        };
      };
    };

    search.Service.searxng = {
      metadata.labels.app = "searxng";
      spec = {
        type = "ClusterIP";
        selector.app = "searxng";
        ports = [
          {
            name = "http";
            port = 8080;
            targetPort = 8080;
            protocol = "TCP";
          }
        ];
      };
    };

    search.Ingress.searxng = {
      metadata = { labels.app = "searxng"; annotations."caddy.ingress.kubernetes.io/disable-ssl-redirect" = "true"; };
      spec = { ingressClassName = "caddy"; rules = [
        { host = "search.lan"; http.paths = [{ path = "/"; pathType = "Prefix"; backend.service = { name = "searxng"; port.number = 8080; }; }]; }
        { host = "search.cluster.local"; http.paths = [{ path = "/"; pathType = "Prefix"; backend.service = { name = "searxng"; port.number = 8080; }; }]; }
      ]; };
    };

    search.NetworkPolicy.allow-searxng-ingress = {
      metadata.labels = {
        app = "searxng";
        policy = "allow-ingress";
      };
      spec = {
        podSelector.matchLabels.app = "searxng";
        policyTypes = [ "Ingress" ];
        ingress = [
          {
            from = [
              { namespaceSelector.matchLabels.name = "ingress-system"; }
            ];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
            ];
          }
          {
            from = [ { podSelector = { }; } ];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
            ];
          }
        ];
      };
    };

    search.NetworkPolicy.allow-searxng-egress = {
      metadata.labels = {
        app = "searxng";
        policy = "allow-egress";
      };
      spec = {
        podSelector.matchLabels.app = "searxng";
        policyTypes = [ "Egress" ];
        egress = [
          {
            to = [
              { ipBlock.cidr = "0.0.0.0/0"; }
            ];
            ports = [
              {
                protocol = "TCP";
                port = 80;
              }
              {
                protocol = "TCP";
                port = 443;
              }
            ];
          }
          {
            to = [
              { namespaceSelector.matchLabels.name = "kube-system"; }
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

    # Migrated from searxng/05-valkey.yaml
    # Valkey (Redis-compatible) cache for SearXNG
    search.Deployment.valkey = {
      metadata.labels = {
        app = "valkey";
        component = "cache";
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "valkey";
        strategy.type = "Recreate";
        template = {
          metadata.labels = {
            app = "valkey";
            component = "cache";
          };
          spec = {
            automountServiceAccountToken = false;
            nodeName = "nexus";
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 999;
              runAsGroup = 999;
              fsGroup = 999;
              seccompProfile.type = "RuntimeDefault";
            };
            containers = {
              _namedlist = true;
              valkey = {
                image = "valkey/valkey:8.1";
                imagePullPolicy = "IfNotPresent";
                command = [ "valkey-server" "--save" "" "--appendonly" "no" "--bind" "0.0.0.0" "--port" "6379" ];
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = [ "ALL" ];
                };
                ports = [
                  {
                    containerPort = 6379;
                    name = "valkey";
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    memory = "64Mi";
                    cpu = "50m";
                  };
                  limits = {
                    memory = "256Mi";
                    cpu = "200m";
                  };
                };
                volumeMounts = {
                  _namedlist = true;
                  data.mountPath = "/data";
                };
                readinessProbe = {
                  exec.command = [ "valkey-cli" "ping" ];
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                  timeoutSeconds = 3;
                  failureThreshold = 3;
                };
                livenessProbe = {
                  exec.command = [ "valkey-cli" "ping" ];
                  initialDelaySeconds = 10;
                  periodSeconds = 30;
                  timeoutSeconds = 3;
                  failureThreshold = 3;
                };
              };
            };
            volumes = {
              _namedlist = true;
              data.emptyDir.medium = "";
            };
          };
        };
      };
    };

    search.Service.valkey = {
      metadata.labels = {
        app = "valkey";
        component = "cache";
      };
      spec = {
        type = "ClusterIP";
        selector.app = "valkey";
        ports = [
          {
            name = "valkey";
            port = 6379;
            targetPort = 6379;
            protocol = "TCP";
          }
        ];
      };
    };
  };
}
