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
      stringData = { postgres-password = "frostbite"; };
    };

    StatefulSet.frostbite-postgres = {
      metadata.labels = managed // {
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
            securityContext = { fsGroup = 999; };
            containers._namedlist = true;
            containers.postgres = {
              image = postgresImage;
              imagePullPolicy = "IfNotPresent";
              ports._namedlist = true;
              ports.postgres = { containerPort = 5432; protocol = "TCP"; };
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
                requests = { cpu = "250m"; memory = "256Mi"; };
                limits = { cpu = "500m"; memory = "512Mi"; };
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
        ports.postgres = { port = 5432; targetPort = 5432; protocol = "TCP"; };
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
            securityContext = { runAsUser = 0; runAsGroup = 0; fsGroup = 100; };
            containers = {
              _namedlist = true;
              ingest = {
                image = "docker.io/library/python:3.13-alpine";
                command = ["sh" "-c" "pip install --quiet pg8000 && python3 /scripts/ingest.py"];
                env = {
                  _namedlist = true;
                  PG_HOST = { name = "PG_HOST"; value = "frostbite-postgres"; };
                  PG_DB   = { name = "PG_DB";   value = "frostbite"; };
                  PG_USER = { name = "PG_USER"; value = "frostbite"; };
                  PG_PASSWORD.valueFrom.secretKeyRef = { name = "frostbite-secrets"; key = "postgres-password"; };
                };
                resources = {
                  requests = {cpu = "100m"; memory = "128Mi";};
                  limits = {cpu = "500m"; memory = "512Mi";};
                };
                volumeMounts = { _namedlist = true; scripts = {mountPath = "/scripts";}; };
              };
            };
            volumes = {
              _namedlist = true;
              scripts = {
                name = "scripts";
                configMap = { name = "frostbite-data-ingest-script"; defaultMode = 493; };
              };
            };
          };
        };
      };
    };

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

      PG_HOST     = os.environ["PG_HOST"]
      PG_DB       = os.environ["PG_DB"]
      PG_USER     = os.environ["PG_USER"]
      PG_PASSWORD = os.environ["PG_PASSWORD"]
      STATCAN_WDS = os.environ.get("STATCAN_WDS_URL", "https://www150.statcan.gc.ca/t1/wds/rest")
      SERVER_PORT = int(os.environ.get("PORT", "3002"))

      import socket as _socket, time as _time
      def _resolve_pg():
          for _ in range(5):
              try: return _socket.gethostbyname(PG_HOST)
              except: _time.sleep(1)
          return PG_HOST
      _PG_IP = _resolve_pg()

      _gov_client = httpx.Client(verify=False, timeout=15)

      def get_db():
          conn = pg8000.connect(host=_PG_IP, port=5432, database=PG_DB, user=PG_USER, password=PG_PASSWORD, timeout=10)
          conn.autocommit = True
          return conn
      TOOLS = [
          {
              "name": "search_statcan",
              "description": "Search Statistics Canada Web Data Service for cube metadata matching a query.",
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
          """Search StatCan WDS for cube metadata matching a query."""
          query = arguments.get("query", "")
          try:
              resp = _gov_client.get(f"{STATCAN_WDS}/getAllCubesListLite")
              resp.raise_for_status()
              cubes = resp.json()
              results = []
              for obj in cubes:
                  title = (obj.get("cubeTitleEn") or obj.get("cubeTitleFr") or "")[:300]
                  if query.lower() in title.lower():
                      results.append({
                          "productId": obj.get("productId"),
                          "cansimId": obj.get("cansimId"),
                          "cubeTitleEn": title,
                          "startDate": obj.get("cubeStartDate"),
                      })
              return json.dumps({"query": query, "count": len(results), "results": results[:20]})
          except Exception as e:
              return json.dumps({"error": str(e)})

      def get_gov_releases(arguments):
          """Query gov_releases_cache table."""
          jurisdiction = arguments.get("jurisdiction", "")
          category = arguments.get("category", "")
          limit = arguments.get("limit", 20)
          try:
              conn = get_db()
              cur = conn.cursor()
              if category and category != "all":
                  cur.execute(
                      "SELECT id, source, jurisdiction, title, data_url, release_date "
                      "FROM gov_releases_cache WHERE jurisdiction = %s AND category ILIKE %s "
                      "ORDER BY release_date DESC NULLS LAST LIMIT %s",
                      (jurisdiction, f"%{category}%", limit),
                  )
              else:
                  cur.execute(
                      "SELECT id, source, jurisdiction, title, data_url, release_date "
                      "FROM gov_releases_cache WHERE jurisdiction = %s "
                      "ORDER BY release_date DESC NULLS LAST LIMIT %s",
                      (jurisdiction, limit),
                  )
              rows = cur.fetchall()
              conn.close()
              results = [
                  {"id": r[0], "source": r[1], "jurisdiction": r[2],
                   "title": r[3], "data_url": r[4],
                   "release_date": str(r[5]) if r[5] else None}
                  for r in rows
              ]
              return json.dumps({"results": results})
          except Exception as e:
              return json.dumps({"error": str(e)})

      def get_citation(arguments):
          """Query citation_hashes table joined with articles."""
          article_id = arguments.get("article_id")
          try:
              conn = get_db()
              cur = conn.cursor()
              cur.execute(
                  "SELECT ch.id, ch.article_id, a.url, ch.content_hash, "
                  "       ch.algorithm, ch.hash_length, ch.computed_at, ch.verified_count "
                  "FROM citation_hashes ch "
                  "JOIN articles a ON a.id = ch.article_id "
                  "WHERE ch.article_id = %s",
                  (article_id,),
              )
              rows = cur.fetchall()
              conn.close()
              results = [
                  {"id": r[0], "article_id": r[1], "article_url": r[2],
                   "content_hash": r[3], "algorithm": r[4], "hash_length": r[5],
                   "computed_at": str(r[6]) if r[6] else None,
                   "verified_count": r[7]}
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
                  "SELECT a.url, ch.content_hash, ch.algorithm, ch.computed_at, "
                  "       gr.title, gr.jurisdiction, gr.data_url "
                  "FROM citation_hashes ch "
                  "JOIN articles a ON a.id = ch.article_id "
                  "LEFT JOIN LATERAL ("
                  "  SELECT title, jurisdiction, data_url FROM gov_releases_cache "
                  "  ORDER BY release_date DESC NULLS LAST LIMIT 5"
                  ") gr ON true "
                  "WHERE ch.article_id = %s "
                  "ORDER BY ch.computed_at DESC NULLS LAST LIMIT 10",
                  (article_id,),
              )
              rows = cur.fetchall()
              conn.close()
              results = [
                  {"article_url": r[0], "content_hash": r[1], "algorithm": r[2],
                   "computed_at": str(r[3]) if r[3] else None,
                   "gov_title": r[4], "gov_jurisdiction": r[5], "gov_data_url": r[6]}
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
              return jsonrpc_response({"content": [{"type": "text", "text": result_text}]}, req_id)
          except Exception as e:
              return jsonrpc_error(-32603, f"Tool error: {e}", req_id)

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

      if __name__ == "__main__":
          print(f"[mcp] Frostbite Gazette MCP server starting on port {SERVER_PORT}")
          server = HTTPServer(("0.0.0.0", SERVER_PORT), MCPHandler)
          print("[mcp] Ready to accept connections")
          server.serve_forever()
    '';

    Deployment.frostbite-mcp = {
      metadata.labels = managed // {
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
            securityContext = { runAsUser = 0; runAsGroup = 0; fsGroup = 100; };
            containers = {
              _namedlist = true;
              mcp = {
                image = "docker.io/library/python:3.13-alpine";
                imagePullPolicy = "IfNotPresent";
                command = [
                  "sh" "-c"
                  "pip install --quiet httpx pg8000 && python3 /scripts/mcp_server.py"
                ];
                ports._namedlist = true;
                ports.http = { containerPort = 3002; protocol = "TCP"; };
                env = {
                  _namedlist = true;
                  PG_HOST = { name = "PG_HOST"; value = "frostbite-postgres"; };
                  PG_DB   = { name = "PG_DB";   value = "frostbite"; };
                  PG_USER = { name = "PG_USER"; value = "frostbite"; };
                  PG_PASSWORD.valueFrom.secretKeyRef = { name = "frostbite-secrets"; key = "postgres-password"; };
                  STATCAN_WDS_URL = { name = "STATCAN_WDS_URL"; value = "https://www150.statcan.gc.ca/t1/wds/rest"; };
                  PORT = { name = "PORT"; value = "3002"; };
                };
                resources = {
                  requests = {cpu = "100m"; memory = "128Mi";};
                  limits = {cpu = "500m"; memory = "512Mi";};
                };
                livenessProbe = {
                  httpGet = { path = "/health"; port = 3002; };
                  initialDelaySeconds = 30;
                  periodSeconds = 60;
                };
                readinessProbe = {
                  httpGet = { path = "/ready"; port = 3002; };
                  initialDelaySeconds = 60;
                  periodSeconds = 10;
                };
                volumeMounts = { _namedlist = true; scripts.mountPath = "/scripts"; };
              };
            };
            volumes = {
              _namedlist = true;
              scripts = {
                name = "scripts";
                configMap = { name = "frostbite-mcp-scripts"; defaultMode = 493; };
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
        ports.http = { port = 3002; targetPort = 3002; protocol = "TCP"; };
      };
    };
  };
}
