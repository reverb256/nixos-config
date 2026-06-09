{
  lib,
  config,
  ...
}: let
  # Import port registry (SSOT for NodePort values)
  ports = import ../kubernetes/service-ports.nix;

  # Import cluster constants (SSOT for IPs, VIP, subnet)
  cluster = import ../kubernetes/cluster.nix;

  # Helper: build a service entry with consistent defaults
  mkService = {
    name,
    namespace,
    port,
    nodePort ? null,
    lan ? "",
    protocol ? "http",
    backend ? null,
  }: let
    effectiveNodePort =
      if nodePort != null
      then nodePort
      else ports.${name} or null;
  in {
    inherit name namespace port protocol;
    nodePort = effectiveNodePort;
    lan =
      if lan != ""
      then lan
      else "${name}.lan";
    backend =
      if backend != null
      then backend
      else "${name}.${namespace}.svc.cluster.local:${toString port}";
    url = "${protocol}://127.0.0.1:${toString (
      if effectiveNodePort != null
      then effectiveNodePort
      else port
    )}";
    dns = "${name}.${namespace}.svc.cluster.local";
  };
  # ── Service Registry ──────────────────────────────────────────────
  # Each entry defines how a service is accessed both inside and outside
  # the cluster. The Caddy router uses these definitions to generate
  # reverse_proxy directives. Edit here to add/modify services.
  #
  # Fields:
  #   name        - Short name (used as .lan hostname: <name>.lan)
  #   namespace   - K8s namespace
  #   port        - Internal cluster port
  #   nodePort    - NodePort override (falls back to service-ports.nix)
  #   lan         - Public .lan hostname (override if different from <name>.lan)
  #   protocol    - http or https (for backend proxy scheme)
  #   backend     - Explicit backend override (skips DNS construction)
  #   auth        - Authentication type: "forward_auth", "none", or "passthrough"
  #   tlsBackend  - Whether backend requires TLS (e.g., self-signed certs)
in {
  options.services.registry = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = name;
        };
        namespace = lib.mkOption {
          type = lib.types.str;
          default = "default";
        };
        port = lib.mkOption {type = lib.types.int;};
        nodePort = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
        };
        lan = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
        protocol = lib.mkOption {
          type = lib.types.str;
          default = "http";
        };
        backend = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        auth = lib.mkOption {
          type = lib.types.str;
          default = "none";
        };
        tlsBackend = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
      };
    }));
    default = {};
    description = "Central service registry for Caddy routing and cluster access";
  };

  config = {
    services.registry = {
      # ── Authentication & SSO ───────────────────────────────────────
      casdoor = mkService {
        name = "casdoor";
        namespace = "auth";
        port = 8000;
        auth = "none"; # Auth endpoint itself — no forward_auth
      };

      oauth2-proxy = mkService {
        name = "oauth2-proxy";
        namespace = "auth";
        port = 4180;
        auth = "none"; # Proxy endpoint — called by Caddy forward_auth
      };

      # ── AI / Inference ────────────────────────────────────────────
      ai-inference-gateway = mkService {
        name = "ai-inference-gateway";
        namespace = "ai-inference";
        port = 8080;
        auth = "forward_auth";
      };

      open-webui = mkService {
        name = "open-webui";
        namespace = "ai-inference";
        port = 8080;
        auth = "forward_auth";
      };

      qdrant = mkService {
        name = "qdrant";
        namespace = "ai-inference";
        port = 6333;
        auth = "forward_auth";
      };

      redis = mkService {
        name = "redis";
        namespace = "ai-inference";
        port = 6379;
        auth = "none"; # Internal only, accessed via ClusterIP DNS
      };

      privacy-filter = mkService {
        name = "privacy-filter";
        namespace = "ai-inference";
        port = 8080;
        auth = "forward_auth";
      };

      # ── LLM Serving ───────────────────────────────────────────────
      llama-zephyr = mkService {
        name = "llama-server-zephyr";
        namespace = "ai-inference";
        port = 1237;
        auth = "forward_auth";
      };

      llama-zephyr-3060ti = mkService {
        name = "llama-vllm-3060ti";
        namespace = "ai-inference";
        port = 8040;
        auth = "forward_auth";
      };

      llama-sentry = mkService {
        name = "llama-server-sentry";
        namespace = "ai-inference";
        port = 1235;
        auth = "forward_auth";
      };

      # ── Infrastructure ────────────────────────────────────────────
      n8n = mkService {
        name = "n8n";
        namespace = "automation";
        port = 5678;
        auth = "forward_auth";
      };

      haven = mkService {
        name = "haven";
        namespace = "haven";
        port = 3000;
        auth = "forward_auth";
        tlsBackend = true; # Self-signed cert
      };

      vaultwarden = mkService {
        name = "vaultwarden";
        namespace = "vaultwarden";
        port = 80;
        auth = "none"; # Has its own OIDC auth
      };

      # ── Search ────────────────────────────────────────────────────
      searxng = mkService {
        name = "searxng";
        namespace = "search";
        port = 8080;
        auth = "none"; # Public search
      };

      vane = mkService {
        name = "vane";
        namespace = "search";
        port = 30900;
        auth = "forward_auth";
      };

      # ── Dashboard & Monitoring ────────────────────────────────────
      grafana = mkService {
        name = "grafana";
        namespace = "monitoring";
        port = 3000;
        auth = "forward_auth";
      };

      glance = mkService {
        name = "glance";
        namespace = "dashboard";
        port = 3000;
        auth = "forward_auth";
      };

      # ── Mission Control ───────────────────────────────────────────
      mission-control = mkService {
        name = "mission-control";
        namespace = "orchestration";
        port = 3000;
        auth = "forward_auth";
      };

      # ── removed ────────────────────────────────────────────────────
      removed-controller = mkService {
        name = "removed-controller";
        namespace = "removed";
        port = 8083;
        auth = "forward_auth";
      };

      removed-ui = mkService {
        name = "removed-ui";
        namespace = "removed";
        port = 8080;
        auth = "forward_auth";
      };

      # ── Communication ─────────────────────────────────────────────
      gitea = mkService {
        name = "gitea";
        namespace = "ai-inference";
        port = 3000;
        auth = "forward_auth";
      };

      # ── maplespike (external/edge) ─────────────────────────────────
      maplespike-api = mkService {
        name = "maplespike-api";
        namespace = "maplespike";
        port = 8082;
        lan = "maplespike-api.lan";
        auth = "forward_auth";
      };

      maplespike-mcp = mkService {
        name = "maplespike-mcp";
        namespace = "maplespike";
        port = 3001;
        lan = "maplespike-mcp.lan";
        auth = "forward_auth";
      };

      maplespike-portal = mkService {
        name = "maplespike-portal";
        namespace = "maplespike";
        port = 8080;
        lan = "maplespike.lan";
        auth = "forward_auth";
      };

      maplespike-status = mkService {
        name = "maplespike-status";
        namespace = "maplespike";
        port = 3001;
        lan = "status.maplespike.lan";
        auth = "forward_auth";
      };

      # ── Dev Environment ───────────────────────────────────────────
      dev-maplespike-api = mkService {
        name = "dev-maplespike-api";
        namespace = "maplespike-dev";
        port = 8082;
        lan = "dev-maplespike-api.lan";
        auth = "forward_auth";
      };

      dev-maplespike-mcp = mkService {
        name = "dev-maplespike-mcp";
        namespace = "maplespike-dev";
        port = 3001;
        lan = "dev-maplespike-mcp.lan";
        auth = "forward_auth";
      };

      dev-maplespike-portal = mkService {
        name = "dev-maplespike-portal";
        namespace = "maplespike-dev";
        port = 8080;
        lan = "dev.maplespike.lan";
        auth = "forward_auth";
      };

      # ── Prod Environment (maplespike-prod) ──────────────────────
      maplespike-prod-api = mkService {
        name = "maplespike-api";
        namespace = "maplespike-prod";
        port = 8082;
        lan = "maplespike-api.lan";
        auth = "forward_auth";
      };

      maplespike-prod-mcp = mkService {
        name = "maplespike-mcp";
        namespace = "maplespike-prod";
        port = 3001;
        lan = "maplespike-mcp.lan";
        auth = "forward_auth";
      };

      maplespike-prod-portal = mkService {
        name = "maplespike-portal";
        namespace = "maplespike-prod";
        port = 8080;
        lan = "maplespike.lan";
        auth = "forward_auth";
      };

      # ── Staging Environment (maplespike-staging) ─────────────────
      maplespike-staging-api = mkService {
        name = "maplespike-api";
        namespace = "maplespike-staging";
        port = 8082;
        lan = "staging.maplespike.lan";
        auth = "forward_auth";
      };

      maplespike-staging-mcp = mkService {
        name = "maplespike-mcp";
        namespace = "maplespike-staging";
        port = 3001;
        lan = "staging.maplespike-mcp.lan";
        auth = "forward_auth";
      };

      maplespike-staging-portal = mkService {
        name = "maplespike-portal";
        namespace = "maplespike-staging";
        port = 8080;
        lan = "staging.maplespike.lan";
        auth = "forward_auth";
      };

      # ── K8s API (hostNetwork) ─────────────────────────────────────
      k8s-api = mkService {
        name = "k8s-api";
        namespace = "default";
        port = 6443;
        lan = "k8s.lan";
        auth = "passthrough";
      };

      # ── Mining Proxy ──────────────────────────────────────────────
      xmrig-proxy = mkService {
        name = "xmrig-proxy";
        namespace = "mining";
        port = 3333;
        lan = "xmrig-proxy.lan";
        auth = "none";
        protocol = "stratum+tcp"; # Non-HTTP protocol
      };
    };
  };
}
