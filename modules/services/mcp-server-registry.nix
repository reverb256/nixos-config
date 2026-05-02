{...}: let
  servers = {
    # Local stdio servers (Nix packages providing mcp-<name> commands)
    filesystem = {
      type = "npm";
      package = "@modelcontextprotocol/server-filesystem";
      args = ["/etc/nixos" "/home/j_kro"];
    };

    git = {
      type = "uvx";
      package = "mcp-server-git";
    };

    fetch = {
      type = "uvx";
      package = "mcp-server-fetch";
    };

    context7 = {
      type = "npm";
      package = "@upstash/context7-mcp";
      env = {CONTEXT7_API_KEY_FILE = "";};
    };

    playwright = {type = "custom";};
    chrome-devtools = {type = "custom";};

    # MCP gateway bridge to AI Inference Gateway
    gateway = {
      type = "custom";
      command = "/etc/nixos/scripts/mcp-gateway-bridge";
      env.GATEWAY_URL = "http://10.15.67.242:8080";
    };

    # SearXNG search via local wrapper script
    searxng = {
      type = "custom";
      command = "/data/agents/mcp-bridges/searxng-mcp.sh";
    };

    # Casdoor SSO bridge (temporary until native MCP Auth)
    casdoor = {
      type = "custom";
      command = "python3";
      args = ["/data/agents/mcp-bridges/casdoor-mcp-bridge.py"];
    };

    # NixOS helper (Claude Code only — uses uvx)
    nixos = {
      type = "custom";
      claudeOnly = true;
      command = "uvx";
      args = ["mcp-nixos"];
    };

    # NixOS cluster management (built package; mainProgram = "nixos-cluster-mcp", not "mcp-nixos-cluster")
    nixos-cluster = {
      type = "nix";
      package = "nixos-cluster-mcp";
      command = "nixos-cluster-mcp";
    };

    # Kubernetes MCP (K8s deployment in infra namespace, streamable HTTP)
    # Hermes connects via K8s service DNS; other tools use ClusterIP
    kubernetes = {
      type = "http";
      url = "http://kubernetes-mcp.infra.svc.cluster.local:8080/mcp";
    };
  };

  mkCommand = name: "mcp-${name}";
in {
  inherit servers mkCommand;
}