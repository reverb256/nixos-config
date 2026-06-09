# ─────────────────────────────────────────────────────────────────
# Service Port Registry — single source of truth for all cluster
# NodePort assignments. Every .lan service that routes through the
# host Caddy gets its port defined here. K8s Helm charts MUST use
# these same static ports.
#
# Convention: <service-name> = <NodePort>;
#   - The name matches the .lan hostname prefix.
#   - Ports are in the 30xxx range for K8s NodePorts.
#   - Host-process ports (< 10000) are excluded.
#
# Add a new entry here BEFORE deploying the K8s Service with
# the matching nodePort. If it's not in this file, Caddy won't
# route to it.
# ─────────────────────────────────────────────────────────────────
{
  # ── maplespike (namespace: maplespike-prod) ─────────────────
  maplespike-api = 31283; # API server (8082 → 31283)
  maplespike-mcp = 31745; # MCP server (3001 → 31745)
  maplespike-portal = 30964; # Static portal (8080 → 30964)
  maplespike-status = 31832; # Uptime Kuma (3001 → 31832)
  # ── maplespike-dev (namespace: maplespike-dev) ────────────────
  dev-maplespike-api = 31284; # Dev API (8082 → 31284)
  dev-maplespike-mcp = 31746; # Dev MCP (3001 → 31746)
  dev-maplespike-portal = 30965; # Dev portal (8080 → 30965)

  # ── ai-inference (namespace: ai-inference) ─────────────────
  ai-inference-gateway = 30880; # AI Inference Gateway
  frostbite-mcp = 30760; # Data ingestion MCP
  gitea = 30954; # Gitea git service
  llama-server-sentry = 30793; # llama.cpp on sentry
  open-webui = 32080; # Open WebUI
  qdrant = 30632; # Vector database

  # ── auth (namespace: auth) ─────────────────────────────────
  casdoor = 32556; # SSO provider
  oauth2-proxy = 30890; # OAuth2 proxy

  # ── automation (namespace: automation) ─────────────────────
  n8n = 32127;

  # ── dashboard (namespace: dashboard) ───────────────────────
  glance = 32200;

  # ── haven (namespace: haven) ───────────────────────────────
  haven = 32100;


  # ── monitoring (namespace: monitoring) ─────────────────────
  grafana = 32102;

  # ── orchestration (namespace: orchestration) ───────────────
  mission-control = 32101;

  # ── search (namespace: search) ─────────────────────────────
  searxng = 32081;
  privacy-filter = 30935;
  vane = 30900;

  # ── vaultwarden (namespace: vaultwarden) ───────────────────
  vaultwarden = 32110;
  vaultwarden-ws = 32111; # WebSocket port
}
