{
  config,
  lib,
  ...
}: let
  postgresImage = "docker.io/library/postgres:16-alpine";
  targetNode = "nexus";
  ns = "ai-inference";
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
    "app.kubernetes.io/part-of" = "frostbite-gazette";
  };
in {
  config.kubernetes.objects.${ns} = {
    Secret.frostbite-secrets = {
      type = "Opaque";
      # TODO: Fill from agenix key `frostbite-postgres` (see modules/system/agenix-secrets-registry.nix)
      stringData = {postgres-password = "";};
    };

    StatefulSet.frostbite-postgres = {
      metadata.labels =
        managed
        // {
          "app.kubernetes.io/component" = "database";
          "app" = "frostbite-postgres";
        };
      spec = {
        serviceName = "frostbite-postgres";
        replicas = 1;
        selector.matchLabels = {"app" = "frostbite-postgres";};
        template = {
          metadata.labels = {
            "app" = "frostbite-postgres";
            "app.kubernetes.io/component" = "database";
          };
          spec = {
            securityContext = {fsGroup = 999;};
            containers._namedlist = true;
            containers.postgres = {
              image = postgresImage;
              imagePullPolicy = "IfNotPresent";
              ports._namedlist = true;
              ports.postgres = {
                containerPort = 5432;
                protocol = "TCP";
              };
              env._namedlist = true;
              env = {
                POSTGRES_DB.value = "frostbite";
                POSTGRES_USER.value = "frostbite";
                POSTGRES_PASSWORD.valueFrom.secretKeyRef = {
                  name = "frostbite-secrets";
                  key = "postgres-password";
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
                exec.command = ["pg_isready" "-U" "frostbite" "-d" "frostbite"];
                initialDelaySeconds = 20;
                periodSeconds = 10;
                timeoutSeconds = 5;
                failureThreshold = 6;
              };
              readinessProbe = {
                exec.command = ["pg_isready" "-U" "frostbite" "-d" "frostbite"];
                initialDelaySeconds = 5;
                periodSeconds = 5;
                timeoutSeconds = 3;
                failureThreshold = 3;
              };
              volumeMounts._namedlist = true;
              volumeMounts.data.mountPath = "/var/lib/postgresql/data";
            };
          };
        };
        volumeClaimTemplates = [
          {
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              storageClassName = "local-path";
              resources.requests.storage = "5Gi";
            };
          }
        ];
      };
    };

    Service.frostbite-postgres = {
      metadata.labels = managed // {"app.kubernetes.io/component" = "database";};
      spec = {
        type = "ClusterIP";
        selector = {"app" = "frostbite-postgres";};
        ports._namedlist = true;
        ports.postgres = {
          port = 5432;
          targetPort = 5432;
          protocol = "TCP";
        };
      };
    };

    # Init SQL removed — tables already exist in the live DB.

    # v4: pg8000 with IP caching
    ConfigMap.frostbite-data-ingest-script.data."ingest.py" = ''
      #!/usr/bin/env python3
      """Frostbite Gazette: civic data ingest."""
      import hashlib, json, os, ssl, sys
      import urllib.request, urllib.error
      import pg8000

      PG_HOST     = os.environ["PG_HOST"]
      PG_DB       = os.environ["PG_DB"]
      PG_USER     = os.environ["PG_USER"]
      PG_PASSWORD = os.environ["PG_PASSWORD"]

      _ssl_ctx = ssl.create_default_context()
      _ssl_ctx.check_hostname = False
      _ssl_ctx.verify_mode = ssl.CERT_NONE

      import socket as _socket
      def _resolve_pg():
          for _ in range(5):
              try: return _socket.gethostbyname(PG_HOST)
              except: time.sleep(1)
          return PG_HOST  # fallback
      _PG_IP = _resolve_pg()
      def get_db():
          conn = pg8000.connect(host=_PG_IP, port=5432, database=PG_DB, user=PG_USER, password=PG_PASSWORD, timeout=10)
          conn.autocommit = True
          return conn

      def fetch_statcan_cubes(conn):
          url = "https://www150.statcan.gc.ca/t1/wds/rest/getAllCubesListLite"
          print("[statcan] Fetching cube list ...")
          try:
              with urllib.request.urlopen(url, timeout=60, context=_ssl_ctx) as r:
                  cubes = json.loads(r.read())
          except Exception as e:
              print(f"[statcan] ERROR: {e}")
              return
          print(f"[statcan] Got {len(cubes)} cubes, inserting ...")
          cur = conn.cursor()
          inserted = 0
          for cube in cubes:
              title = (cube.get("cubeTitleEn") or "")[:500]
              pid = str(cube.get("productId", ""))
              if not title or not pid:
                  continue
              data_url = f"https://www150.statcan.gc.ca/t1/en/tbl/{pid}"
              date_str = cube.get("cubeStartDate", "")
              try:
                  cur.execute(
                      "INSERT INTO gov_releases_cache (source, jurisdiction, title, data_url, release_date, category, retrieved_at) "
                      "VALUES (%s, %s, %s, %s, %s, %s, NOW()) "
                      "ON CONFLICT (source, title) DO UPDATE SET retrieved_at = NOW()",
                      ("statcan", "federal", title, data_url, date_str or None, "statistics"),
                  )
                  inserted += 1
              except Exception as e:
                  pass  # skip duplicates silently
          print(f"[statcan] Inserted/updated {inserted} cubes")

      CKAN_PORTALS = [
          ("Federal (open.canada.ca)", "https://open.canada.ca/data/en/api/3/action/package_search", "federal"),
          # ("Ontario",              "https://data.ontario.ca/api/3/action/package_search",              "ontario"),  # 502 as of 2026-05
          ("BC",                      "https://catalog.data.gov.bc.ca/api/3/action/package_search",           "bc"),
          ("Alberta",                 "https://open.alberta.ca/api/3/action/package_search",                 "alberta"),
          ("Quebec",                  "https://www.donneesquebec.ca/api/3/action/package_search",             "quebec"),
      ]

      def fetch_ckan_portal(name, url, jurisdiction, conn):
          print(f"[ckan] Fetching from {name} ...")
          payload = json.dumps({"rows": 20, "start": 0}).encode()
          req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json", "User-Agent": "FrostbiteGazette/1.0"})
          try:
              with urllib.request.urlopen(req, timeout=30, context=_ssl_ctx) as r:
                  data = json.loads(r.read())
          except Exception as e:
              print(f"[ckan] {name} ERROR: {e}")
              return
          results = (data.get("result") or {}).get("results") or []
          cur = conn.cursor()
          for pkg in results:
              title = (pkg.get("title") or "")[:500]
              pkg_url = pkg.get("url") or ""
              try:
                  cur.execute(
                      "INSERT INTO gov_releases_cache (source, jurisdiction, title, data_url, category, retrieved_at) "
                      "VALUES (%s, %s, %s, %s, %s, NOW()) "
                      "ON CONFLICT (source, title) DO UPDATE SET retrieved_at = NOW()",
                      (name, jurisdiction, title, pkg_url, "opendata"),
                  )
              except Exception as e:
                  print(f"[ckan] {name} DB insert error: {e}")
          print(f"[ckan] {name}: {len(results)} packages")

      def main():
          print("=== Frostbite Gazette Data Ingest ===")
          conn = get_db()
          fetch_statcan_cubes(conn)
          for name, url, jurisdiction in CKAN_PORTALS:
              fetch_ckan_portal(name, url, jurisdiction, conn)
          conn.close()
          print("=== Ingest complete ===")

      if __name__ == "__main__":
          main()
    '';

    CronJob.frostbite-data-ingest = {
      metadata.labels = managed // {app = "frostbite-data-ingest";};
      spec = {
        schedule = "0 */6 * * *";
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 1;
        jobTemplate.spec.template = {
          metadata.labels = {app = "frostbite-data-ingest";};
          spec = {
            nodeName = "nexus";
            restartPolicy = "OnFailure";
            securityContext = {
              runAsUser = 0;
              runAsGroup = 0;
              fsGroup = 100;
            };
            containers = {
              _namedlist = true;
              ingest = {
                image = "docker.io/library/python:3.13-alpine";
                command = ["sh" "-c" "pip install --quiet pg8000 && python3 /scripts/ingest.py"];
                env = {
                  _namedlist = true;
                  PG_HOST = {
                    name = "PG_HOST";
                    value = "frostbite-postgres";
                  };
                  PG_DB = {
                    name = "PG_DB";
                    value = "frostbite";
                  };
                  PG_USER = {
                    name = "PG_USER";
                    value = "frostbite";
                  };
                  PG_PASSWORD.valueFrom.secretKeyRef = {
                    name = "frostbite-secrets";
                    key = "postgres-password";
                  };
                };
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
                volumeMounts = {
                  _namedlist = true;
                  scripts = {mountPath = "/scripts";};
                };
              };
            };
            volumes = {
              _namedlist = true;
              scripts = {
                name = "scripts";
                configMap = {
                  name = "frostbite-data-ingest-script";
                  defaultMode = 493;
                };
              };
            };
          };
        };
      };
    };

    # MCP server - image deprecated and removed, replace with new MCP server image
    frostbite.Deployment.frostbite-mcp = {
      metadata.labels =
        managed
        // {
          app = "frostbite-mcp";
          "app.kubernetes.io/component" = "mcp-server";
        };
      spec = {
        replicas = 1;
        selector.matchLabels = {app = "frostbite-mcp";};
        template = {
          metadata.labels = {
            app = "frostbite-mcp";
            "app.kubernetes.io/component" = "mcp-server";
          };
          spec = {
            nodeName = targetNode;
            securityContext = {
              runAsUser = 0;
              runAsGroup = 0;
              fsGroup = 100;
            };
            containers = {
              _namedlist = true;
              mcp = {
                image = "none"; # FIXME: MCP server image removed, replace with new image
                imagePullPolicy = "IfNotPresent";
                ports._namedlist = true;
                ports.http = {
                  containerPort = 3002;
                  protocol = "TCP";
                };
                env = {
                  _namedlist = true;
                  PG_HOST = {
                    name = "PG_HOST";
                    value = "frostbite-postgres";
                  };
                  PG_DB = {
                    name = "PG_DB";
                    value = "frostbite";
                  };
                  PG_USER = {
                    name = "PG_USER";
                    value = "frostbite";
                  };
                  PG_PASSWORD.valueFrom.secretKeyRef = {
                    name = "frostbite-secrets";
                    key = "postgres-password";
                  };
                  STATCAN_WDS_URL = {
                    name = "STATCAN_WDS_URL";
                    value = "https://www150.statcan.gc.ca/t1/wds/rest";
                  };
                  PORT = {
                    name = "PORT";
                    value = "3002";
                  };
                };
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
                    path = "/health";
                    port = 3002;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 60;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 3002;
                  };
                  initialDelaySeconds = 60;
                  periodSeconds = 10;
                };
              };
            };
            volumes = {
              _namedlist = true;
            };
          };
        };
      };
    };

    Service.frostbite-mcp = {
      metadata.labels = managed // {app = "frostbite-mcp";};
      spec = {
        type = "NodePort";
        selector = {app = "frostbite-mcp";};
        ports._namedlist = true;
        ports.http = {
          port = 3002;
          targetPort = 3002;
          nodePort = 30760;
          protocol = "TCP";
        };
      };
    };
  };
}
