# Claude Code Router - Proxy for routing Claude Code to different LLM providers
# https://github.com/musistudio/claude-code-router
#
# This service acts as a proxy between Claude Code and various LLM providers.
# It routes requests based on configuration, allowing you to use different
# models for different tasks (default, thinking, long context, etc.)
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.claude-code-router;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;

  # CLI wrapper script
  ccrScript = pkgs.writeShellScriptBin "ccr" ''
    #!${pkgs.bash}/bin/bash
    set -e

    CCR_DIR="${cfg.stateDir}"
    PORT="${toString cfg.port}"

    case "$1" in
      start)
        systemctl start claude-code-router
        echo "Claude Code Router started on port $PORT"
        ;;
      stop)
        systemctl stop claude-code-router
        echo "Claude Code Router stopped"
        ;;
      restart)
        systemctl restart claude-code-router
        echo "Claude Code Router restarted"
        ;;
      status)
        systemctl status claude-code-router --no-pager
        echo ""
        echo "Health check:"
        if ${pkgs.curl}/bin/curl -sf "http://localhost:$PORT/health" 2>/dev/null; then
          echo " - OK"
        else
          echo " - FAILED"
        fi
        ;;
      logs)
        journalctl -u claude-code-router -f
        ;;
      config)
        ${pkgs.jq}/bin/jq . "$CCR_DIR/config.json"
        ;;
      edit)
        if [ -n "$EDITOR" ]; then
          $EDITOR "$CCR_DIR/config.json"
        else
          ${pkgs.nano}/bin/nano "$CCR_DIR/config.json"
        fi
        echo "Restarting service..."
        systemctl restart claude-code-router
        ;;
      ui)
        cd "$CCR_DIR"
        ${pkgs.nodejs_22}/bin/npx @musistudio/claude-code-router ui
        ;;
      model)
        cd "$CCR_DIR"
        ${pkgs.nodejs_22}/bin/npx @musistudio/claude-code-router model
        ;;
      activate)
        echo "# Add these to your shell profile to use Claude Code with the router:"
        echo ""
        echo "export ANTHROPIC_AUTH_TOKEN=\"any-string\""
        echo "export ANTHROPIC_BASE_URL=\"http://localhost:$PORT\""
        echo "export NO_PROXY=\"localhost,127.0.0.1\""
        ;;
      *)
        echo "Claude Code Router CLI"
        echo ""
        echo "Usage: ccr <command>"
        echo ""
        echo "Commands:"
        echo "  start     Start the router service"
        echo "  stop     Stop the router service"
        echo "  restart  Restart the router service"
        echo "  status    Show service status and health"
        echo "  logs     Follow service logs"
        echo "  config   Show current configuration (pretty)"
        echo "  edit     Edit configuration (requires restart)"
        echo "  ui       Open web UI for configuration"
        echo "  model    Interactive model selector"
        echo "  activate Show environment variables for Claude Code"
        exit 1
        ;;
    esac
  '';

in
{
  options.services.claude-code-router = {
    enable = mkEnableOption "Claude Code Router - route Claude Code to different LLM providers";

    port = mkOption {
      type = types.port;
      default = 3456;
      description = "Port for the Claude Code Router proxy server";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port (router binds to localhost by default)";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/claude-code-router";
      description = "Directory for router state files";
    };

    zai = {
      apiKeyFile = mkOption {
        type = types.path;
        default = "";
        description = "Path to file containing Z.AI API key (agenix runtime path)";
      };

      defaultModel = mkOption {
        type = types.str;
        default = "glm-5";
        description = "Default model for Z.AI";
      };

      thinkModel = mkOption {
        type = types.str;
        default = "glm-5.1";
        description = "Model to use for thinking tasks";
      };
    };
  };

  config = mkIf cfg.enable {
    # Firewall configuration (localhost-only by default for security)
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall (lib.mkOptionDefault [ cfg.port ]);

    # System packages - nodejs and CLI wrapper
    environment.systemPackages = [
      pkgs.nodejs_22
      ccrScript
    ];

    # Create state directory
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 root root -"
    ];

    # Setup service - generates config.json at runtime with API key from secret file
    systemd.services.claude-code-router-setup = {
      description = "Setup Claude Code Router config";
      wantedBy = [ "multi-user.target" ];
      before = [ "claude-code-router.service" ];
      path = [
        pkgs.jq
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "ccr-setup" ''
          API_KEY=$(cat ${cfg.zai.apiKeyFile})
          ${pkgs.jq}/bin/jq -n \
            --arg api_key "$API_KEY" \
            --arg api_url "https://api.z.ai/api/coding/paas/v4/chat/completions" \
            --arg default_model "${cfg.zai.defaultModel}" \
            --arg think_model "${cfg.zai.thinkModel}" \
            '{
              LOG: true,
              LOG_LEVEL: "info",
              API_TIMEOUT_MS: 600000,
              NON_INTERACTIVE_MODE: false,
              Providers: [{
                name: "zai",
                api_base_url: $api_url,
                api_key: $api_key,
                models: ["glm-4.5","glm-4.5-air","glm-4.6","glm-4.7","glm-4.7-flash","glm-5","glm-5-turbo","glm-5.1"],
                transformer: { use: ["deepseek"] }
              }],
              Router: {
                default: "zai," + $default_model,
                think: "zai," + $think_model,
                longContext: "zai,glm-4.7",
                longContextThreshold: 60000
              }
            }' > ${cfg.stateDir}/config.json
        '';
        RemainAfterExit = true;
      };
    };

    # Main systemd service
    systemd.services.claude-code-router = {
      description = "Claude Code Router - LLM proxy service";
      after = [
        "network.target"
        "network-online.target"
        "claude-code-router-setup.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "claude-code-router-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        NODE_ENV = "production";
        HOME = "/root";
      };

      path = [
        pkgs.nodejs_22
        pkgs.coreutils
        pkgs.bash
        pkgs.gnugrep
        pkgs.which
      ];

      serviceConfig = {
        Type = "simple";
        User = "root";
        Group = "root";
        WorkingDirectory = cfg.stateDir;

        # Restart policy
        Restart = "on-failure";
        RestartSec = "10s";

        # Resource limits
        MemoryMax = "1G";
        MemoryHigh = "750M";

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "claude-code-router";

        # Security hardening (relaxed for npx which needs sh, npm cache)
        NoNewPrivileges = true;
        PrivateTmp = false;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.stateDir "/root/.npm" "/tmp" ];

        ExecStart = "${pkgs.nodejs_22}/bin/npx @musistudio/claude-code-router start --port ${toString cfg.port} --config ${cfg.stateDir}/config.json";
      };
    };

    # Health check timer + service
    systemd.timers.claude-code-router-health = {
      description = "Claude Code Router periodic health check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "1min";
        Unit = "claude-code-router-health.service";
      };
    };

    systemd.services.claude-code-router-health = {
      description = "Claude Code Router health check";
      after = [ "claude-code-router.service" ];
      wants = [ "claude-code-router.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -sf http://localhost:${toString cfg.port}/health";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
}
