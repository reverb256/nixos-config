# AI Inference Service Configuration for Zephyr
# RTX 3090 (24GB) + RTX 3060 Ti (8GB)
# Gateway runs in K8s on Zephyr (hostNetwork, port 8081) with ZAI backend
{...}: {
  services.ai-inference = {
    enable = true;

    # Backend: ZAI cloud API (local inference removed)
    backend = {
      type = "zai";
      zai = {
        enable = true;
        apiKeyFile = "/run/secrets/zai-api-key";
      };
    };

    # Gateway runs in K8s (hostNetwork, port 8081), not systemd
    gateway = {
      enable = false;
      host = "127.0.0.1";
      port = 8081;
      workers = 4;
    };

    # Routing: ZAI models by context/complexity
    routing = {
      enable = true;
      defaultModel = "glm-4.7";
      rules = [
        {
          minTokens = 0;
          maxTokens = 4096;
          model = "glm-4.5-air";
          priority = 10;
        }
        {
          minTokens = 4097;
          maxTokens = 131072;
          model = "glm-4.7";
          priority = 20;
        }
        {
          minTokens = 131073;
          maxTokens = 999999;
          model = "glm-4.6";
          priority = 30;
        }
      ];
    };

    auth.mode = "none";

    monitoring = {
      enable = true;
      port = 9190;
    };
  };
}
