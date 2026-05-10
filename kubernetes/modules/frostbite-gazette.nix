{
  config,
  lib,
  ...
}: let
  # ── Version pinning ──────────────────────────────────────────────────
  postgresImage = "docker.io/library/postgres:16-alpine";

  # ── Cluster placement ────────────────────────────────────────────────
  # All workloads on Nexus (46GB RAM).
  targetNode = "nexus";
  ns = "ai-inference";

  # ── Labels ───────────────────────────────────────────────────────────
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
    "app.kubernetes.io/part-of" = "frostbite-gazette";
  };
in {
  # ══════════════════════════════════════════════════════════════════════
  # FROSTBITE GAZETTE — Civic Intelligence Upgrade
  # ══════════════════════════════════════════════════════════════════════
  #
  # Future Caddy routes (add to host-services.nix or ingress.nix):
  #   frostbite-api.lan  -> frostbite-ask.ai-inference.svc.cluster.local:3001
  #   frostbite-mcp.lan  -> frostbite-mcp.ai-inference.svc.cluster.local:3002
  #
  # ══════════════════════════════════════════════════════════════════════

  config.kubernetes.objects.${ns} = {

    # ══════════════════════════════════════════════════════════════════════
    # SECRETS
    # ══════════════════════════════════════════════════════════════════════
    Secret.frostbite-secrets = {
      type = "Opaque";
      stringData = {
        # Placeholder — replace with agenix-managed secret in production.
        # Managed by agenix: apply_secret ai-inference frostbite-secrets postgres-password
        postgres-password = "frostbite";
      };
    };

    # ══════════════════════════════════════════════════════════════════════
    # POSTGRES — Frostbite Gazette database
    # ══════════════════════════════════════════════════════════════════════
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
            securityContext = {
              fsGroup = 999;
            };
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
              storageClassName = "local-path-immediate";
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

    # ══════════════════════════════════════════════════════════════════════
    # CONFIGMAP — Database init SQL
    # ══════════════════════════════════════════════════════════════════════
    ConfigMap.frostbite-data-init.data."init.sql" = ''
      -- Frostbite Gazette: database schema
      -- Auto-created by init container / manual apply.

      CREATE TABLE IF NOT EXISTS gov_data_releases (
        id            SERIAL PRIMARY KEY,
        source        TEXT NOT NULL,
        jurisdiction  TEXT NOT NULL,
        title         TEXT NOT NULL,
        release_url   TEXT,
        description   TEXT,
        release_date  TIMESTAMP DEFAULT NOW(),
        ingested_at   TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_gov_releases_source
        ON gov_data_releases (source);
      CREATE INDEX IF NOT EXISTS idx_gov_releases_jurisdiction
        ON gov_data_releases (jurisdiction);
      CREATE INDEX IF NOT EXISTS idx_gov_releases_date
        ON gov_data_releases (release_date);

      CREATE TABLE IF NOT EXISTS citation_hashes (
        id            SERIAL PRIMARY KEY,
        article_id    INTEGER NOT NULL,
        article_url   TEXT NOT NULL,
        content_hash  TEXT NOT NULL,
        hash_algo     TEXT NOT NULL DEFAULT 'sha256',
        created_at    TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_citation_article_id
        ON citation_hashes (article_id);
      CREATE INDEX IF NOT EXISTS idx_citation_hash
        ON citation_hashes (content_hash);

      CREATE TABLE IF NOT EXISTS data_journalism (
        id            SERIAL PRIMARY KEY,
        title         TEXT NOT NULL,
        topic         TEXT,
        source_url    TEXT,
        summary       TEXT,
        published_at  TIMESTAMP DEFAULT NOW(),
        created_at    TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_journalism_topic
        ON data_journalism (topic);
      CREATE INDEX IF NOT EXISTS idx_journalism_published
        ON data_journalism (published_at);
    '';

    # ══════════════════════════════════════════════════════════════════════
    # CONFIGMAP — Data ingest script
    # ══════════════════════════════════════════════════════════════════════
    ConfigMap.frostbite-data-ingest-script.data."ingest.py" = ''
      #!/usr/bin/env python3
      """Frostbite Gazette: civic data ingest.

      Fetches government data releases from Canadian portals and hashes
      existing articles for citation verification.  Runs as a CronJob
      every 6 hours on Nexus.
      """
      import hashlib
      import json
      import os
      import ssl
      import sys
      import urllib.request
      import urllib.error

      import pg8000

      # ── Environment ──────────────────────────────────────────────────
      PG_HOST     = os.environ["PG_HOST"]
      PG_DB       = os.environ["PG_DB"]
      PG_USER     = os.environ["PG_USER"]
      PG_PASSWORD = os.environ["PG_PASSWORD"]
      WORKER_API  = os.environ.get("WORKER_API", "https://api.frostbitegazette.ca")

      # Unverified SSL context for government HTTPS endpoints.
      _ssl_ctx = ssl.create_default_context()
      _ssl_ctx.check_hostname = False
      _ssl_ctx.verify_mode = ssl.CERT_NONE

      # Verified context for the worker API.
      _ssl_ctx_verified = ssl.create_default_context()

      # ── Database helper ──────────────────────────────────────────────
      def get_db():
          conn = pg8000.connect(
              host=PG_HOST,
              database=PG_DB,
              user=PG_USER,
              password=PG_PASSWORD,
          )
          conn.autocommit = True
          return conn

      # ── StatCan releases ─────────────────────────────────────────────
      def fetch_statcan_releases(conn):
          url = "https://www150.statcan.gc.ca/t1/wds/rest/getLatestReleases"
          print("[statcan] Fetching latest releases ...")
          try:
              req = urllib.request.Request(url, method="POST",
                                          data=b'{"pageSize": 20}',
                                          headers={"Content-Type": "application/json"})
              with urllib.request.urlopen(req, timeout=30, context=_ssl_ctx) as r:
                  data = json.loads(r.read())
          except Exception as e:
              print(f"[statcan] ERROR: {e}")
              return
          items = data.get("object") or []
          cur = conn.cursor()
          for item in items:
              title = (item.get("titleEn") or item.get("title", ""))[:500]
              ref_date = item.get("referencePeriod", "")
              pid = item.get("productId", "")
              release_url = f"https://www150.statcan.gc.ca/n1/en/catalogue/{pid}" if pid else None
              try:
                  cur.execute(
                      "INSERT INTO gov_data_releases (source, jurisdiction, title, release_url, release_date) "
                      "VALUES (%s, %s, %s, %s, %s) ON CONFLICT DO NOTHING",
                      ("statcan", "federal", title, release_url, ref_date or None),
                  )
              except Exception as e:
                  print(f"[statcan] DB insert error: {e}")
          print(f"[statcan] Processed {len(items)} releases")

      # ── CKAN portal fetcher ──────────────────────────────────────────
      CKAN_PORTALS = [
          ("Federal (open.canada.ca)", "https://open.canada.ca/data/en/api/3/action/package_search", "federal"),
          ("Ontario",                 "https://data.ontario.ca/api/3/action/package_search",                 "ontario"),
          ("BC",                      "https://catalog.data.gov.bc.ca/api/3/action/package_search",           "bc"),
          ("Alberta",                 "https://open.alberta.ca/api/3/action/package_search",                 "alberta"),
          ("Quebec",                  "https://www.donneesquebec.ca/api/3/action/package_search",             "quebec"),
      ]

      def fetch_ckan_portal(name, url, jurisdiction, conn):
          print(f"[ckan] Fetching from {name} ...")
          payload = json.dumps({"rows": 20, "start": 0}).encode()
          req = urllib.request.Request(url, data=payload,
                                      headers={"Content-Type": "application/json"})
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
                      "INSERT INTO gov_data_releases (source, jurisdiction, title, release_url) "
                      "VALUES (%s, %s, %s, %s) ON CONFLICT DO NOTHING",
                      (name, jurisdiction, title, pkg_url),
                  )
              except Exception as e:
                  print(f"[ckan] {name} DB insert error: {e}")
          print(f"[ckan] {name}: {len(results)} packages")

      # ── Article hashing ──────────────────────────────────────────────
      def hash_articles(conn):
          print("[hasher] Fetching articles from worker API ...")
          articles_url = f"{WORKER_API}/api/articles?limit=50"
          try:
              with urllib.request.urlopen(articles_url, timeout=20, context=_ssl_ctx_verified) as r:
                  articles = json.loads(r.read())
          except Exception as e:
              print(f"[hasher] ERROR fetching articles: {e}")
              return

          if isinstance(articles, dict):
              articles = articles.get("articles") or articles.get("data") or []

          cur = conn.cursor()
          hashed = 0
          for article in articles:
              article_id = article.get("id")
              article_url = article.get("url") or article.get("source_url")
              if not article_id or not article_url:
                  continue
              try:
                  with urllib.request.urlopen(article_url, timeout=15, context=_ssl_ctx) as r:
                      content = r.read()
                  sha = hashlib.sha256(content).hexdigest()
                  cur.execute(
                      "INSERT INTO citation_hashes (article_id, article_url, content_hash) "
                      "VALUES (%s, %s, %s) ON CONFLICT DO NOTHING",
                      (article_id, article_url, sha),
                  )
                  # POST hash back to worker API.
                  hash_url = f"{WORKER_API}/api/articles/{article_id}/hash"
                  payload = json.dumps({"hash": sha}).encode()
                  req = urllib.request.Request(hash_url, data=payload,
                                              method="POST",
                                              headers={"Content-Type": "application/json"})
                  with urllib.request.urlopen(req, timeout=10, context=_ssl_ctx_verified):
                      pass
                  hashed += 1
              except Exception as e:
                  print(f"[hasher] article {article_id}: {e}")
          print(f"[hasher] Hashed {hashed}/{len(articles)} articles")

      # ── Main ─────────────────────────────────────────────────────────
      def main():
          print("=== Frostbite Gazette Data Ingest ===")
          conn = get_db()

          fetch_statcan_releases(conn)

          for name, url, jurisdiction in CKAN_PORTALS:
              fetch_ckan_portal(name, url, jurisdiction, conn)

          hash_articles(conn)

          conn.close()
          print("=== Ingest complete ===")

      if __name__ == "__main__":
          main()
    '';

    # ══════════════════════════════════════════════════════════════════════
    # CRONJOB — Data ingest (every 6h)
    # ══════════════════════════════════════════════════════════════════════
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
                command = [
                  "sh" "-c"
                  "pip install --quiet pg8000 && python3 /scripts/ingest.py"
                ];
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
                  WORKER_API = {
                    name = "WORKER_API";
                    value = "https://api.frostbitegazette.ca";
                  };
                };
                resources = {
                  requests = {cpu = "100m"; memory = "128Mi";};
                  limits = {cpu = "500m"; memory = "512Mi";};
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
                  defaultMode = "0755";
                };
              };
            };
          };
        };
      };
    };

    # ══════════════════════════════════════════════════════════════════════
    # CONFIGMAP — MCP server script
    # ══════════════════════════════════════════════════════════════════════
    ConfigMap.frostbite-mcp-scripts.data."mcp_server.py" = ''
      #!/usr/bin/env python3
      """Frostbite Gazette: MCP server wrapping Canadian government data APIs.

      Exposes tools via HTTP transport (JSON-RPC 2.0) for AI agents.
      Uses stdlib + httpx + pg8000 only.
      """
      import json
      import os
      import sys
      from http.server import HTTPServer, BaseHTTPRequestHandler
      from urllib.parse import urlparse, parse_qs

      import httpx
      import pg8000

      # ── Environment ──────────────────────────────────────────────────
      PG_HOST       = os.environ["PG_HOST"]
      PG_DB         = os.environ["PG_DB"]
      PG_USER       = os.environ["PG_USER"]
      PG_PASSWORD   = os.environ["PG_PASSWORD"]
      STATCAN_WDS   = os.environ.get("STATCAN_WDS_URL", "https://www150.statcan.gc.ca/t1/wds/rest")
      SERVER_PORT   = int(os.environ.get("PORT", "3002"))

      # Unverified HTTP client for government HTTPS endpoints.
      _gov_client = httpx.Client(verify=False, timeout=15)

      # ── Database helper ──────────────────────────────────────────────
      def get_db():
          conn = pg8000.connect(
              host=PG_HOST,
              database=PG_DB,
              user=PG_USER,
              password=PG_PASSWORD,
          )
          conn.autocommit = True
          return conn

      # ── MCP Tools ────────────────────────────────────────────────────
      TOOLS = [
          {
              "name": "search_statcan",
              "description": "Search Statistics Canada Web Data Service for cube metadata or series info.",
              "inputSchema": {
                  "type": "object",
                  "properties": {
                      "query": {"type": "string", "description": "Search query for StatCan data."},
                  },
                  "required": ["query"],
              },
          },
          {
              "name": "get_gov_releases",
              "description": "Query government data releases from the frostbite-postgres database.",
              "inputSchema": {
                  "type": "object",
                  "properties": {
                      "jurisdiction": {"type": "string", "description": "Jurisdiction filter (federal, ontario, bc, alberta, quebec)."},
                      "category": {"type": "string", "description": "Category/source filter."},
                      "limit": {"type": "integer", "description": "Max results to return (default 20)."},
                  },
                  "required": ["jurisdiction", "category", "limit"],
              },
          },
          {
              "name": "get_citation",
              "description": "Get citation hash information for an article from the database.",
              "inputSchema": {
                  "type": "object",
                  "properties": {
                      "article_id": {"type": "integer", "description": "The article ID to look up."},
                  },
                  "required": ["article_id"],
              },
          },
          {
              "name": "search_ckan",
              "description": "Search a CKAN open data portal (default: open.canada.ca).",
              "inputSchema": {
                  "type": "object",
                  "properties": {
                      "query": {"type": "string", "description": "Search query."},
                      "portal": {"type": "string", "description": "Portal name: open.canada.ca (default), ontario, bc, alberta, quebec."},
                  },
                  "required": ["query", "portal"],
              },
          },
          {
              "name": "get_article_data",
              "description": "Get comprehensive article data joining articles, citation hashes, and government release cache.",
              "inputSchema": {
                  "type": "object",
                  "properties": {
                      "article_id": {"type": "integer", "description": "The article ID to look up."},
                  },
                  "required": ["article_id"],
              },
          },
      ]

      CKAN_PORTALS = {
          "open.canada.ca": "https://open.canada.ca/data/en/api/3/action/package_search",
          "ontario":        "https://data.ontario.ca/api/3/action/package_search",
          "bc":             "https://catalog.data.gov.bc.ca/api/3/action/package_search",
          "alberta":        "https://open.alberta.ca/api/3/action/package_search",
          "quebec":         "https://www.donneesquebec.ca/api/3/action/package_search",
      }

      def search_statcan(arguments):
          """Search StatCan WDS for cube metadata or series info."""
          query = arguments.get("query", "")
          try:
              resp = _gov_client.get(
                  f"{STATCAN_WDS}/getCubeMetadataList",
                  params={"productId": 0},
              )
              resp.raise_for_status()
              data = resp.json()
              results = []
              for obj in (data.get("object") or []):
                  title = (obj.get("titleEn") or obj.get("title", ""))[:300]
                  if query.lower() in title.lower():
                      results.append({
                          "productId": obj.get("productId"),
                          "cubeTitleEn": title,
                      })
              if not results:
                  resp2 = _gov_client.get(
                      f"{STATCAN_WDS}/getSeriesInfoFromVector",
                      params={"vectorId": 0},
                  )
                  resp2.raise_for_status()
                  data2 = resp2.json()
                  for obj in (data2.get("object") or []):
                      desc = (obj.get("vectorDescription") or "")[:300]
                      if query.lower() in desc.lower():
                          results.append({
                              "vectorId": obj.get("vectorId"),
                              "description": desc,
                          })
              return json.dumps({"results": results[:20]})
          except Exception as e:
              return json.dumps({"error": str(e)})

      def get_gov_releases(arguments):
          """Query gov_data_releases table."""
          jurisdiction = arguments.get("jurisdiction", "")
          category = arguments.get("category", "")
          limit = arguments.get("limit", 20)
          try:
              conn = get_db()
              cur = conn.cursor()
              if category and category != "all":
                  cur.execute(
                      "SELECT id, source, jurisdiction, title, release_url, release_date "
                      "FROM gov_data_releases WHERE jurisdiction = %s AND source ILIKE %s "
                      "ORDER BY release_date DESC LIMIT %s",
                      (jurisdiction, f"%{category}%", limit),
                  )
              else:
                  cur.execute(
                      "SELECT id, source, jurisdiction, title, release_url, release_date "
                      "FROM gov_data_releases WHERE jurisdiction = %s "
                      "ORDER BY release_date DESC LIMIT %s",
                      (jurisdiction, limit),
                  )
              rows = cur.fetchall()
              conn.close()
              results = [
                  {"id": r[0], "source": r[1], "jurisdiction": r[2],
                   "title": r[3], "url": r[4], "date": str(r[5]) if r[5] else None}
                  for r in rows
              ]
              return json.dumps({"results": results})
          except Exception as e:
              return json.dumps({"error": str(e)})

      def get_citation(arguments):
          """Query citation_hashes table."""
          article_id = arguments.get("article_id")
          try:
              conn = get_db()
              cur = conn.cursor()
              cur.execute(
                  "SELECT id, article_id, article_url, content_hash, hash_algo, created_at "
                  "FROM citation_hashes WHERE article_id = %s",
                  (article_id,),
              )
              rows = cur.fetchall()
              conn.close()
              results = [
                  {"id": r[0], "article_id": r[1], "url": r[2],
                   "hash": r[3], "algo": r[4], "created": str(r[5]) if r[5] else None}
                  for r in rows
              ]
              return json.dumps({"results": results})
          except Exception as e:
              return json.dumps({"error": str(e)})

      def search_ckan(arguments):
          """Search a CKAN portal."""
          query = arguments.get("query", "")
          portal = arguments.get("portal", "open.canada.ca")
          base_url = CKAN_PORTALS.get(portal, CKAN_PORTALS["open.canada.ca"])
          try:
              resp = _gov_client.post(
                  base_url,
                  json={"rows": 20, "start": 0, "q": query},
                  headers={"Content-Type": "application/json"},
              )
              resp.raise_for_status()
              data = resp.json()
              packages = (data.get("result") or {}).get("results") or []
              results = [
                  {"name": p.get("name"), "title": p.get("title"),
                   "url": p.get("url"), "notes": (p.get("notes") or "")[:300]}
                  for p in packages[:20]
              ]
              return json.dumps({"portal": portal, "results": results})
          except Exception as e:
              return json.dumps({"error": str(e)})

      def get_article_data(arguments):
          """Join articles + citation_hashes + gov_releases_cache for context."""
          article_id = arguments.get("article_id")
          try:
              conn = get_db()
              cur = conn.cursor()
              cur.execute(
                  "SELECT ch.article_url, ch.content_hash, ch.hash_algo, ch.created_at, "
                  "       gr.title, gr.jurisdiction, gr.release_url "
                  "FROM citation_hashes ch "
                  "LEFT JOIN LATERAL ("
                  "  SELECT title, jurisdiction, release_url FROM gov_data_releases "
                  "  ORDER BY release_date DESC LIMIT 5"
                  ") gr ON true "
                  "WHERE ch.article_id = %s "
                  "ORDER BY ch.created_at DESC LIMIT 10",
                  (article_id,),
              )
              rows = cur.fetchall()
              conn.close()
              results = [
                  {"url": r[0], "hash": r[1], "algo": r[2], "created": str(r[3]) if r[3] else None,
                   "gov_title": r[4], "gov_jurisdiction": r[5], "gov_url": r[6]}
                  for r in rows
              ]
              return json.dumps({"article_id": article_id, "results": results})
          except Exception as e:
              return json.dumps({"error": str(e)})

      TOOL_DISPATCH = {
          "search_statcan":  search_statcan,
          "get_gov_releases": get_gov_releases,
          "get_citation":     get_citation,
          "search_ckan":      search_ckan,
          "get_article_data": get_article_data,
      }

      # ── JSON-RPC helpers ─────────────────────────────────────────────
      def jsonrpc_response(result, req_id=None):
          return {"jsonrpc": "2.0", "result": result, "id": req_id}

      def jsonrpc_error(code, message, req_id=None):
          return {"jsonrpc": "2.0", "error": {"code": code, "message": message}, "id": req_id}

      def handle_tools_list(req_id=None):
          return jsonrpc_response({"tools": TOOLS}, req_id)

      def handle_tools_call(name, arguments, req_id=None):
          handler = TOOL_DISPATCH.get(name)
          if not handler:
              return jsonrpc_error(-32601, f"Unknown tool: {name}", req_id)
          try:
              result_text = handler(arguments or {})
              return jsonrpc_response({
                  "content": [{"type": "text", "text": result_text}],
              }, req_id)
          except Exception as e:
              return jsonrpc_error(-32603, f"Tool error: {e}", req_id)

      # ── HTTP handler ─────────────────────────────────────────────────
      class MCPHandler(BaseHTTPRequestHandler):
          def log_message(self, format, *args):
              print(f"[mcp] {args[0]}")

          def do_GET(self):
              if self.path == "/health":
                  self._json(200, {"status": "ok"})
              elif self.path == "/ready":
                  self._json(200, {"ready": True})
              else:
                  self._json(404, {"error": "not found"})

          def do_POST(self):
              if self.path != "/":
                  self._json(404, {"error": "not found"})
                  return
              try:
                  body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                  data = json.loads(body) if body else {}
              except Exception:
                  self._json(400, {"error": "invalid json"})
                  return

              method = data.get("method", "")
              req_id = data.get("id")
              params = data.get("params") or {}

              if method == "tools/list":
                  self._json(200, handle_tools_list(req_id))
              elif method == "tools/call":
                  name = params.get("name", "")
                  arguments = params.get("arguments") or {}
                  self._json(200, handle_tools_call(name, arguments, req_id))
              else:
                  self._json(200, jsonrpc_error(-32601, f"Unknown method: {method}", req_id))

          def _json(self, code, obj):
              payload = json.dumps(obj).encode()
              self.send_response(code)
              self.send_header("Content-Type", "application/json")
              self.send_header("Content-Length", str(len(payload)))
              self.end_headers()
              self.wfile.write(payload)

      # ── Main ─────────────────────────────────────────────────────────
      if __name__ == "__main__":
          print(f"[mcp] Frostbite Gazette MCP server starting on port {SERVER_PORT}")
          server = HTTPServer(("0.0.0.0", SERVER_PORT), MCPHandler)
          print("[mcp] Ready to accept connections")
          server.serve_forever()
    '';

    # ══════════════════════════════════════════════════════════════════════
    # DEPLOYMENT — frostbite-mcp
    # ══════════════════════════════════════════════════════════════════════
    Deployment.frostbite-mcp = {
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
                image = "docker.io/library/python:3.13-alpine";
                imagePullPolicy = "IfNotPresent";
                command = [
                  "sh" "-c"
                  "pip install --quiet mcp[cli] httpx pg8000 && python3 /scripts/mcp_server.py"
                ];
                ports._namedlist = true;
                ports.http = {
                  containerPort = 3002;
                  protocol = "TCP";
                };
                env = {
                  _namedlist = true;
                  PG_HOST = {
                    name = "PG_HOST";
                    value = "frostbite-postgres.ai-inference.svc.cluster.local";
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
                  MCP_TRANSPORT = {
                    name = "MCP_TRANSPORT";
                    value = "http";
                  };
                };
                resources = {
                  requests = {cpu = "100m"; memory = "128Mi";};
                  limits = {cpu = "500m"; memory = "512Mi";};
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
                    path = "/ready";
                    port = 3002;
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
                volumeMounts = {
                  _namedlist = true;
                  scripts.mountPath = "/scripts";
                };
              };
            };
            volumes = {
              _namedlist = true;
              scripts = {
                name = "scripts";
                configMap = {
                  name = "frostbite-mcp-scripts";
                  defaultMode = "0755";
                };
              };
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
          protocol = "TCP";
        };
      };
    };
  };
}
