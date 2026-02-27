# AI Services Module
# Template for custom AI interface integration
# This module provides a foundation for your custom AI interface
{pkgs, ...}: {
  # Install AI/LLM development tools and libraries
  environment.systemPackages = with pkgs; [
    # AI development libraries
    python312Packages.openai
    python312Packages.anthropic
    python312Packages.langchain

    # CLI tools for AI interaction
    aichat # ChatGPT-like CLI
    oterm # TUI LLM client

    # Python AI framework
    python312
    python312Packages.pip
    python312Packages.virtualenv
    python312Packages.venvShellHook

    # GPU acceleration for AI
    cudaPackages.cudnn
  ];

  # ============================================================================
  # CUSTOM AI INTERFACE TEMPLATE
  # ============================================================================
  #
  # This section is designed as a template for your custom AI interface.
  # Enable services as needed for your implementation.
  #
  # Example: Local web service for custom AI interface
  # services.your-custom-ai = {
  #   enable = true;
  #   port = 8888;
  #   # Add your configuration here
  # };
  #
  # Example: Systemd user service for AI agent
  # systemd.user.services.your-ai-agent = {
  #   Unit = {
  #     Description = "Custom AI Agent";
  #     After = ["network.target"];
  #   };
  #   Service = {
  #     Type = "simple";
  #     ExecStart = "/path/to/your/ai-agent";
  #     Restart = "on-failure";
  #   };
  #   Install.WantedBy = ["default.target"];
  # };
  #
  # ============================================================================

  # ============================================================================
  # OPTIONAL: OLLAMA (Disabled - using custom interface)
  # ============================================================================
  # Enable if you want to use Ollama as a backend
  # services.ollama = {
  #   enable = false;  # Set to true to enable
  #   acceleration = "cuda";  # or "rocm" for AMD
  #   environment = [
  #     "OLLAMA_HOST=0.0.0.0"
  #   ];
  # };

  # ============================================================================
  # OPTIONAL: OPEN WEBUI (Disabled - using custom interface)
  # ============================================================================
  # services.open-webui = {
  #   enable = false;  # Set to true to enable
  #   host = "127.0.0.1";
  #   port = 8888;
  #   environment = {
  #     "OLLAMA_BASE_URL" = "http://127.0.0.1:11434";
  #   };
  # };

  # ============================================================================
  # AI/LLM DEVELOPMENT SUPPORT
  # ============================================================================

  # Python environment for AI development
  systemd.tmpfiles.rules = [
    "d /var/lib/ai 0755 root root -"
    "d /var/lib/ai/models 0755 root root -"
  ];

  # Environment variables for AI development
  environment.sessionVariables = {
    # CUDA paths for GPU acceleration
    CUDA_HOME = "/run/opengl-driver";
    CUDA_ROOT = "/run/opengl-driver";

    # Model storage paths
    AI_MODELS_DIR = "/var/lib/ai/models";
    AI_DATA_DIR = "/var/lib/ai/data";

    # API endpoints (configure as needed)
    # OPENAI_API_KEY_FILE = "/run/agenix/openai-api-key";
    # ANTHROPIC_API_KEY_FILE = "/run/agenix/anthropic-api-key";
  };

  # ============================================================================
  # NOTES FOR CUSTOM AI INTERFACE SETUP
  # ============================================================================
  #
  # 1. **Web Interface:**
  #    - Create a systemd service in hosts/zephyr/configuration.nix
  #    - Use port 8888 or higher
  #    - Set environment variables for API keys
  #
  # 2. **Background Service:**
  #    - Create systemd user service for persistent AI agent
  #    - Configure restart policy
  #    - Set up logging
  #
  # 3. **GPU Support:**
  #    - CUDA paths are already configured
  #    - CuDNN and cuTENSOR available
  #    - Set `acceleration = "cuda"` in your service
  #
  # 4. **Secrets Management:**
  #    - Use agenix for API keys
  #    - Store in /run/agenix/
  #    - Reference via tokenFile in services
  #
  # 5. **Network Access:**
  #    - Configure firewall in hosts/zephyr/configuration.nix
  #    - Open ports as needed
  #    - Use reverse proxy (nginx/caddy) for HTTPS
  #
  # ============================================================================

  # ============================================================================
  # EXAMPLE: Custom AI Web Service Template
  # ============================================================================
  #
  # services.your-custom-ai = {
  #   enable = true;
  #
  #   # Service configuration
  #   script = ""
  #     #!/bin/sh
  #     export PATH=/run/current-system/sw/bin:$PATH
  #     export AI_MODEL_PATH=/var/lib/ai/models
  #     export CUDA_VISIBLE_DEVICES=0
  #     cd /var/lib/ai
  #     exec your-ai-interface --host 0.0.0.0 --port 8888
  #   '';
  #
  #   # Environment
  #   environment = {
  #     "MODEL_PATH" = "/var/lib/ai/models";
  #     "GPU_LAYERS" = "1";
  #     "API_KEY_FILE" = "/run/agenix/your-api-key";
  #   };
  #
  #   # User to run as
  #   user = "j_kro";
  #
  #   # Auto-restart on failure
  #   restartIfFailed = true;
  #   restartSec = "10s";
  # };
  #
  # ============================================================================

  # Firewall configuration (configure in host config)
  # networking.firewall.allowedTCPPorts = [ 8888 ];
  # networking.firewall.allowedUDPPorts = [ ];
}
