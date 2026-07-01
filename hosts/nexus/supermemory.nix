# Supermemory Configuration for Nexus

Add this to `/etc/nixos/hosts/nexus/configuration.nix`:

```nix
{
  # ... existing imports

  # Supermemory local memory engine
  services.supermemory = {
    enable = true;
    dataDir = "/home/j_kro/.supermemory";
    openaiBaseUrl = "http://sentry.lan:1235/v1";
    openaiApiKey = "sk-dummy-key";
    model = "Qwen3.5-4B-Q4_K_M.gguf";
    port = 6767;
    user = "j_kro";
  };
}
```

## Notes

- Local models: Check if sentry/forge are running Qwen3.5-4B
- K8s service DNS: `llama-server-sentry.ai-inference.svc.cluster.local:1235`
- Fallback to host DNS: `http://sentry.lan:1235/v1`
- Dummy API key for local llama-server (no real auth needed)

## Next Steps

1. Verify sentry is running Qwen3.5-4B
2. Test endpoint: `curl http://sentry.lan:1235/v1/models`
3. Add above config to nexus/configuration.nix
4. Deploy via Colmena
5. Test Supermemory health: `curl http://nexus.lan:6767/v1/health`
6. Configure Hermes MCP