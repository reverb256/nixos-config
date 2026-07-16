{
  cfg,
  pkgs,
  gatewayUrl,
  mkMcpServersJson,
}: let
  nvidiaNimBaseUrl = gatewayUrl + "/v1";
in {
  mkCrushConfig = pkgs.writeShellScript "generate-crush-config" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    CTX7_KEY_PATH="${cfg.context7ApiKeyFile}"
    CONTEXT7_API_KEY="$(cat $CTX7_KEY_PATH 2>/dev/null || echo)"
    NVIDIA_NIM_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
    NVIDIA_NIM_API_KEY="$(cat $NVIDIA_NIM_KEY_PATH 2>/dev/null || echo)"
    ${pkgs.jq}/bin/jq -n \
      --arg ctx7_key "$CONTEXT7_API_KEY" \
      --arg nvidia_key "$NVIDIA_NIM_API_KEY" \
        --arg gateway_base "${gatewayUrl}/v1" \
      --arg nvidia_base "${nvidiaNimBaseUrl}" \
      '{
        "providers":,
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
            "name": "llama.cpp Server (Zephyr 3090)",
            "base_url": "http://10.1.1.110:1237/v1"
          }
        },
        "mcp": {
          ${mkMcpServersJson {keyMode = "resolved";}}
        }
      }' > "/home/${cfg.user}/.config/crush/crush.json"
    chown ${cfg.user}:users "/home/${cfg.user}/.config/crush/crush.json"
    chmod 600 "/home/${cfg.user}/.config/crush/crush.json"
    echo "[ai-coding-tools] Crush config generated"
  '';
}
