{
  cfg,
  pkgs,
  gatewayUrl,
  mkMcpServersJson,
}: {
  mkOmpConfig = pkgs.writeShellScript "generate-omp-config" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail


    mkdir -p "/home/${cfg.user}/.omp/agent"

    # Write mcp.json
        "settings": {"idleTimeout": 30},
        "mcpServers": {
          ${mkMcpServersJson {keyMode = "env";}}
        }
      }' > "/home/${cfg.user}/.omp/agent/mcp.json"

    # Write models.json
    ${pkgs.jq}/bin/jq -n       --arg gateway_base "${gatewayUrl}/v1"       '{
        "providers": {
          "gateway": {
            "baseUrl": ($gateway_base),
            "api": "openai-completions",
            "apiKey": "***",
            "models": [,,
            ]
          },
          "local-vllm": {
            "baseUrl": "http://10.1.1.120:8040/v1",
            "api": "openai-completions",
            "models": [{"id": "qwen3.5-2b-awq", "name": "Qwen 3.5 2B"}]
          },
          "local-llama-zephyr": {
            "baseUrl": "http://10.1.1.110:1237/v1",
            "api": "openai-completions",
            "models": [{"id": "Qwen3.6-35B-A3B", "name": "Qwen3.6 35B"}]
          },
          "local-llama-sentry": {
            "baseUrl": "http://10.1.1.140:1235/v1",
            "api": "openai-completions",
            "models": [{"id": "Qwen3.5-4B", "name": "Qwen3.5 4B"}]
          }
        },
        "modelRoles": {
          "default": "qwen/qwen3.5-397b-a17b",
          "smol": "local/qwen3.5-2b-awq",
          "code": "qwen/qwen3.5-397b-a17b"
        }
      }' > "/home/${cfg.user}/.omp/agent/models.json"

    chown -R ${cfg.user}:users "/home/${cfg.user}/.omp" 2>/dev/null || true
    chmod 644 "/home/${cfg.user}/.omp/agent/mcp.json" "/home/${cfg.user}/.omp/agent/models.json"
    echo "[ai-coding-tools] OMP config generated"
  '';
}
