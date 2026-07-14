{
  cluster,
  nexusPreferredAffinity,
  ...
}: let
  labels = {
    app = "searxng";
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects = {
    # ── Namespace ─────────────────────────────────────────────────
    none.Namespace.search = {
      metadata.labels = {
        name = "search";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    # ── Secret ────────────────────────────────────────────────────
    # Populated by kubectl-apply-k8s-secrets from sops-nix:
    #   secret-key ← /run/secrets/searxng-secret-key
    search.Secret.searxng-secret = {
      type = "Opaque";
      stringData."secret-key" = "";
    };

    # ── ConfigMap: nsswitch (fix musl mdns timeout) ────────────────
    search.ConfigMap.nsswitch-conf = {
      metadata.labels = labels;
      data."nsswitch.conf" = ''
        passwd: files
        group: files
        shadow: files
        hosts: files dns
        networks: files
        protocols: files
        services: files
        ethers: files
        rpc: files
      '';
    };

    # ── ConfigMap: SearXNG settings (single source of truth) ──────
    search.ConfigMap.searxng-settings = {
      metadata.labels = labels;
      data = {
        "limiter.toml" = ''
          [botdetection.ip_limit]
          link_token = false
        '';
        "settings.yml" = ''
          use_default_settings: true

          server:
            limiter: false  # Rate limiting disabled (internal service, no public exposure)
            secret_key: "@SEARXNG_SECRET_KEY@"
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
            autocomplete: ""  # Disable autocomplete for API/agent use
            default_on_categories: [general, science, it, files]

          # Caching: Valkey-backed with extended TTL for better hit rate
          server:
            limiter: false
            secret_key: "@SEARXNG_SECRET_KEY@"
            image_proxy: true
            method: "GET"
            port: 8080
            bind_address: "0.0.0.0"
            default_http_headers:
              Cache-Control: max-age=600

          ui:
            static_use_hash: true
            default_theme: simple

          outgoing:
            request_timeout: 30.0
            max_request_timeout: 60.0
            pool_connections: 100
            pool_maxsize: 50
            enable_http2: true
            using_tor_proxy: true
            retries: 3
            retry_on_http_error:
              - 403
              - 429
              - 500
              - 502
              - 503
              - 504

          valkey:
            url: valkey://valkey.search.svc.cluster.local:6379/0

          engines:
            # -- General --
            - name: google
            - name: bing
            - name: duckduckgo
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

    # ── Deployment: SearXNG ───────────────────────────────────────
    search.Deployment.searxng = {
      metadata.labels = labels;
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "searxng";
        strategy = {
          type = "Recreate";
          rollingUpdate = null;
        };
        template = {
          metadata.labels = labels;
          spec = {
            affinity = nexusPreferredAffinity; # HA: prefer nexus, failover to sentry
            enableServiceLinks = false;
            automountServiceAccountToken = false;
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1001;
              runAsGroup = 1001;
              fsGroup = 1001;
              seccompProfile.type = "RuntimeDefault";
            };
            # The upstream searxng/searxng image ships NO non-root user
            # (its config User is null → runs as root). Because the pod is
            # forced to runAsNonRoot/runAsUser=1001, Python's
            # pwd.getpwuid(1001) in valkeydb.py raises KeyError at init and
            # the process crashes (CrashLoopBackOff). The container is also
            # readOnlyRootFilesystem, so /etc/passwd is immutable. Fix: an
            # initContainer provisions a passwd/group entry for 1001 into a
            # writable emptyDir, overlaid onto the read-only /etc/passwd.
            initContainers = {
              _namedlist = true;
              setup-passwd = {
                image = "searxng/searxng@sha256:dda1ea3a106b448f5e18ef9b3bb8448e92fc7ecccc3f4a0c82b0106f3dfca23b";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  runAsNonRoot = true;
                  runAsUser = 1001;
                  runAsGroup = 1001;
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = ["ALL"];
                };
                command = [
                  "sh"
                  "-c"
                  ''
                    set -e
                    printf 'searxng:x:1001:1001::/home/searxng:/sbin/nologin\n' > /passwd/passwd
                    printf 'searxng:x:1001:\n' > /passwd/group
                    chmod 0644 /passwd/passwd /passwd/group
                  ''
                ];
                volumeMounts = {
                  _namedlist = true;
                  passwd = {
                    mountPath = "/passwd";
                  };
                };
              };
            };
            containers = {
              _namedlist = true;
              searxng = {
                image = "searxng/searxng@sha256:dda1ea3a106b448f5e18ef9b3bb8448e92fc7ecccc3f4a0c82b0106f3dfca23b";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  runAsNonRoot = true;
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = ["ALL"];
                };
                env = {
                  _namedlist = true;
                  SEARXNG_SECRET.valueFrom.secretKeyRef = {
                    name = "searxng-secret";
                    key = "secret-key";
                  };
                  SEARXNG_PORT.value = "8080";
                  SEARXNG_BASE_URL.value = "https://searxng.lan/";
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
                  limiter = {
                    mountPath = "/etc/searxng/limiter.toml";
                    subPath = "limiter.toml";
                    readOnly = true;
                  };
                  data = {
                    mountPath = "/etc/searxng/data";
                  };
                  tmp = {
                    mountPath = "/tmp";
                  };
                  nsswitch = {
                    mountPath = "/etc/nsswitch.conf";
                    subPath = "nsswitch.conf";
                    readOnly = true;
                  };
                  passwd = {
                    mountPath = "/etc/passwd";
                    subPath = "passwd";
                    readOnly = true;
                  };
                  group = {
                    mountPath = "/etc/group";
                    name = "passwd";
                    subPath = "group";
                    readOnly = true;
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              settings.configMap.name = "searxng-settings";
              limiter.configMap = {
                name = "searxng-settings";
                items = [
                  {
                    key = "limiter.toml";
                    path = "limiter.toml";
                  }
                ];
              };
              nsswitch.configMap.name = "nsswitch-conf";
              data.emptyDir = {};
              tmp.emptyDir = {};
              passwd.emptyDir = {};
            };
            tor = {
              image = "nexus:5000/tor-socks:latest";
              imagePullPolicy = "IfNotPresent";
              securityContext = {
                runAsNonRoot = true;
                runAsUser = 1001;
                runAsGroup = 1001;
                allowPrivilegeEscalation = false;
                capabilities.drop = ["ALL"];
                readOnlyRootFilesystem = false;
                seccompProfile.type = "RuntimeDefault";
              };
              ports = [{
                name = "socks";
                containerPort = 9050;
                protocol = "TCP";
              }];
              resources = {
                requests = { memory = "32Mi"; cpu = "30m"; };
                limits = { memory = "64Mi"; cpu = "100m"; };
              };
            };
          };
        };
      };
    };

    # ── Service ───────────────────────────────────────────────────
    search.Service.searxng = {
      metadata.labels = labels;
      spec = {
        type = "NodePort";
        selector.app = "searxng";
        ports = [
          {
            name = "http";
            port = 8080;
            nodePort = 32081;
            targetPort = 8080;
            protocol = "TCP";
          }
        ];
      };
    };

    # ── Deployment: Valkey (cache) ────────────────────────────────
    search.Deployment.valkey = {
      metadata.labels =
        labels
        // {
          app = "valkey";
          component = "cache";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels = {
          app = "valkey";
          component = "cache";
        };
        strategy = {
          type = "Recreate";
          rollingUpdate = null;
        };
        template = {
          metadata.labels =
            labels
            // {
              app = "valkey";
              component = "cache";
            };
          spec = {
            affinity = nexusPreferredAffinity; # HA: prefer nexus, failover to sentry
            automountServiceAccountToken = false;
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
                image = "valkey/valkey:9.0.4";
                imagePullPolicy = "IfNotPresent";
                command = [
                  "valkey-server"
                  "--save"
                  ""
                  "--appendonly"
                  "no"
                  "--bind"
                  "0.0.0.0"
                  "--port"
                  "6379"
                ];
                securityContext = {
                  runAsNonRoot = true;
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = ["ALL"];
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
                readinessProbe = {
                  exec.command = [
                    "valkey-cli"
                    "ping"
                  ];
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                  timeoutSeconds = 3;
                  failureThreshold = 3;
                };
                livenessProbe = {
                  exec.command = [
                    "valkey-cli"
                    "ping"
                  ];
                  initialDelaySeconds = 10;
                  periodSeconds = 30;
                  timeoutSeconds = 3;
                  failureThreshold = 3;
                };
                volumeMounts = {
                  _namedlist = true;
                  data.mountPath = "/data";
                };
              };
            };
            volumes = {
              _namedlist = true;
              data.emptyDir = {};
            };
          };
        };
      };
    };

    search.Service.valkey = {
      metadata.labels =
        labels
        // {
          component = "cache";
        };
      spec = {
        type = "NodePort";
        selector.app = "valkey";
        selector.component = "cache";
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

    # ── NetworkPolicies ───────────────────────────────────────────
    search.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };

    search.NetworkPolicy.allow-searxng-ingress = {
      metadata.labels =
        labels
        // {
          policy = "allow-ingress";
        };
      spec = {
        podSelector.matchLabels.app = "searxng";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [
              {ipBlock.cidr = cluster.subnet;}
              {ipBlock.cidr = cluster.podCidr;}
            ];
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
      metadata.labels =
        labels
        // {
          policy = "allow-egress";
        };
      spec = {
        podSelector.matchLabels.app = "searxng";
        policyTypes = ["Egress"];
        egress = [
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
          {
            to = [{ipBlock.cidr = "0.0.0.0/0";}];
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
          # Valkey access
          {
            to = [{podSelector.matchLabels.app = "valkey";}];
            ports = [
              {
                protocol = "TCP";
                port = 6379;
              }
            ];
          }
        ];
      };
    };

    search.NetworkPolicy.allow-valkey-ingress = {
      metadata.labels = {
        app = "valkey";
        policy = "allow-ingress";
      };
      spec = {
        podSelector.matchLabels.app = "valkey";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{podSelector = {};}];
            ports = [
              {
                protocol = "TCP";
                port = 6379;
              }
            ];
          }
        ];
      };
    };
  };
}
