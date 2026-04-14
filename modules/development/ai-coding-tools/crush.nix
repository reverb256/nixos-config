{
  cfg,
  pkgs,
  mkMcpServersJson,
}:
let
  gatewayUrl = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080";
  nvidiaNimBaseUrl = "https://integrate.api.nvidia.com/v1";
in
{
  mkCrushConfig = pkgs.writeShellScript "generate-crush-config" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    ZAI_KEY_PATH="${cfg.zaiApiKeyFile}"
    ZAI_API_KEY="$(cat $ZAI_KEY_PATH 2>/dev/null || echo)"
    CTX7_KEY_PATH="${cfg.context7ApiKeyFile}"
    CONTEXT7_API_KEY="$(cat $CTX7_KEY_PATH 2>/dev/null || echo)"
    NVIDIA_NIM_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
    NVIDIA_NIM_API_KEY="$(cat $NVIDIA_NIM_KEY_PATH 2>/dev/null || echo)"
    ${pkgs.jq}/bin/jq -n \
      --arg zai_key "$ZAI_API_KEY" \
      --arg ctx7_key "$CONTEXT7_API_KEY" \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
      --arg zai_base "https://api.z.ai/api/coding/paas/v4" \
      --arg gateway_base "${gatewayUrl}/v1" \
      --arg nvidia_base "${nvidiaNimBaseUrl}" \
      '{
        "providers": {
          "zai": {
            "id": "zai",
            "name": "ZAI Provider",
            "base_url": $zai_base,
            "api_key": $zai_key
          },
          "nvidia-nim": {
            "id": "nvidia-nim",
            "name": "NVIDIA NIM",
            "base_url": $nvidia_base,
            "api_key": $nvidia_key
          },
          "lmstudio": {
            "id": "lmstudio",
            "name": "LM Studio (Local)",
            "base_url": "http://127.0.0.1:1234/v1"
          },
          "llama-cpp": {
            "id": "llama-cpp",
            "name": "llama.cpp Server (Nix)",
            "base_url": "http://127.0.0.1:1235/v1"
          }
        },
        "mcp": {
          ${mkMcpServersJson { keyMode = "resolved"; }}
        }
      }' > "/home/${cfg.user}/.config/crush/crush.json"
    chown ${cfg.user}:users "/home/${cfg.user}/.config/crush/crush.json"
    chmod 600 "/home/${cfg.user}/.config/crush/crush.json"
    echo "[ai-coding-tools] Crush config generated"
  '';
}
