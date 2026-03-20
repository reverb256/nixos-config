# N8N Module
# Workflow automation platform (from XNM1)
_: {
  # ============================================================================
  # N8N - Workflow Automation
  # ============================================================================
  # MIGRATED TO KUBERNETES (2026-03-18)
  # Running in ai-inference namespace on cluster nodes
  services.n8n = {
    enable = false;
  };

  # Ensure N8N has proper PATH access
  systemd.services.n8n.serviceConfig.Environment = "PATH=/run/current-system/sw/bin";

  # ============================================================================
  # NOTES
  # ============================================================================
  # N8N will be available at: http://127.0.0.1:5678
  #
  # N8n integrates with:
  # - Ollama (for local LLM workflows)
  # - Searxng (for privacy-preserving search)
  # - Your MCP servers
  # - HTTP/REST APIs
  #
  # First run will prompt for account creation.
}
