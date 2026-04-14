{ lib, ... }: {
  services.ai-inference = {
    enable = true;

    backend = {
      type = "zai";
      zai = {
        enable = true;
        apiKeyFile = "/run/agenix/zai-api-key";
      };
    };

    gateway = {
      enable = false;
      host = "10.1.1.120";
      port = 8081;
      workers = 4;
      middleware.redis.enable = false;
    };

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
