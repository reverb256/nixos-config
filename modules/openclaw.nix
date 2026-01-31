# OpenClaw AI Assistant Module
# Deploys OpenClaw to NixOS nodes with proper configuration and service management

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.openclaw;
  
  # Generate OpenClaw configuration based on node role
  openclawConfig = pkgs.writeText "openclaw.json" (builtins.toJSON {
    meta = {
      lastTouchedVersion = "2026.1.29";
      lastTouchedAt = "2026-01-31T00:00:00.000Z";
    };
    wizard = {
      lastRunAt = "2026-01-31T00:00:00.000Z";
      lastRunVersion = "2026.1.29";
      lastRunCommand = "configure";
      lastRunMode = if cfg.isMaster then "local" else "remote";
    };
    update = {
      channel = "stable";
      checkOnStart = true;
    };
    auth = {
      profiles = if cfg.isMaster then {
        "qwen-portal:default" = {
          provider = "qwen-portal";
          mode = "oauth";
        };
      } else {};
    };
    models = {
      providers = if cfg.isMaster then {
        "qwen-portal" = {
          baseUrl = "https://portal.qwen.ai/v1";
          apiKey = "qwen-oauth";
          api = "openai-completions";
          models = [
            {
              id = "coder-model";
              name = "Qwen Coder";
              reasoning = false;
              input = ["text"];
              cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
              contextWindow = 128000;
              maxTokens = 8192;
            }
            {
              id = "vision-model";
              name = "Qwen Vision";
              reasoning = false;
              input = ["text" "image"];
              cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
              contextWindow = 128000;
              maxTokens = 8192;
            }
          ];
        };
        "ollama" = {
          baseUrl = "http://localhost:11434/v1";
          apiKey = "ollama";
          api = "openai-completions";
          models = [
            {
              id = "glm-4.7-flash";
              name = "GLM-4.7-Flash (30B MoE) - BEST CODING";
              reasoning = false;
              input = ["text"];
              cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
              contextWindow = 128000;
              maxTokens = 4096;
            }
            {
              id = "gpt-oss:20b";
              name = "GPT-OSS-20B (OpenAI) - GENERAL";
              reasoning = false;
              input = ["text"];
              cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
              contextWindow = 128000;
              maxTokens = 4096;
            }
            {
              id = "qwen3-coder:30b";
              name = "Qwen3-Coder-30B (256K context)";
              reasoning = false;
              input = ["text"];
              cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
              contextWindow = 256000;
              maxTokens = 4096;
            }
            {
              id = "devstral-small-2";
              name = "Devstral Small 2 (24B) - AGENTIC";
              reasoning = false;
              input = ["text" "image"];
              cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
              contextWindow = 384000;
              maxTokens = 4096;
            }
            {
              id = "nemotron-3-nano";
              name = "Nemotron 3 Nano (1M context!)";
              reasoning = false;
              input = ["text"];
              cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
              contextWindow = 1000000;
              maxTokens = 4096;
            }
            {
              id = "mistral-small3.1";
              name = "Mistral Small 3.1 (Vision + Fast)";
              reasoning = false;
              input = ["text" "image"];
              cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
              contextWindow = 128000;
              maxTokens = 4096;
            }
            {
              id = "llama3.2:3b";
              name = "Llama 3.2 3B - Fast General";
              reasoning = false;
              input = ["text"];
              cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
              contextWindow = 8192;
              maxTokens = 2048;
            }
            {
              id = "codellama:7b";
              name = "Code Llama 7B - Development";
              reasoning = false;
              input = ["text"];
              cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
              contextWindow = 16384;
              maxTokens = 2048;
            }
          ];
        };
      } else {
        "ollama" = {
          baseUrl = "http://localhost:11434/v1";
          apiKey = "ollama";
          api = "openai-completions";
          models = [
            {
              id = "glm-4.7-flash";
              name = "GLM-4.7-Flash (30B MoE)";
              reasoning = false;
              input = ["text"];
              cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
              contextWindow = 128000;
              maxTokens = 4096;
            }
          ];
        };
      };
    };
    agents = {
      defaults = {
        model = if cfg.isMaster then {
          primary = "qwen-portal/coder-model";
          fallbacks = [
            "ollama/glm-4.7-flash"
            "ollama/devstral-small-2"
            "ollama/nemotron-3-nano"
            "ollama/mistral-small3.1"
          ];
        } else {
          primary = "ollama/glm-4.7-flash";
        };
        imageModel = if cfg.isMaster then {
          primary = "qwen-portal/vision-model";
        } else {};
        models = if cfg.isMaster then {
          "qwen-portal/coder-model" = { alias = "qwen"; };
          "qwen-portal/vision-model" = {};
          "ollama/glm-4.7-flash" = {};
          "ollama/gpt-oss:20b" = {};
          "ollama/qwen3-coder:30b" = {};
          "ollama/devstral-small-2" = {};
          "ollama/nemotron-3-nano" = {};
          "ollama/mistral-small3.1" = {};
          "ollama/llama3.2:3b" = {};
          "ollama/codellama:7b" = {};
        } else {
          "ollama/glm-4.7-flash" = {};
        };
        workspace = "/home/j_kro/.openclaw/workspace";
        compaction = { mode = "safeguard"; };
        maxConcurrent = 4;
        subagents = { maxConcurrent = 8; };
      };
    };
    tools = {
      web = if cfg.isMaster then {
        search = { enabled = true; apiKey = "BSAvecteV2rBDk-NEjx4WOpuvABsRga"; };
        fetch = { enabled = true; };
      } else {
        search = { enabled = false; };
        fetch = { enabled = true; };
      };
      agentToAgent = { enabled = true; allow = ["sisyphus" "opencode"]; };
      exec = { applyPatch = { enabled = false; }; };
    };
    messages = { ackReactionScope = if cfg.isMaster then "group-mentions" else "none"; };
    commands = { native = true; nativeSkills = true; bash = true; };
    hooks = if cfg.isMaster then {
      enabled = true;
      token = "eef381d1a022a2bc9259aedfa2de9d6fc46ce2453d51200e2c0476a81cd7c611";
      internal = {
        enabled = true;
        entries = {
          "boot-md" = { enabled = true; };
          "command-logger" = { enabled = true; };
          "session-memory" = { enabled = true; };
        };
      };
    } else {
      enabled = false;
    };
    channels = if cfg.isMaster then {
      whatsapp = {
        accounts = {};
        capabilities = [];
        dmPolicy = "allowlist";
        selfChatMode = true;
        allowFrom = ["+17802254005"];
        groupPolicy = "allowlist";
        mediaMaxMb = 50;
        actions = { reactions = true; sendMessage = true; polls = true; };
        debounceMs = 0;
      };
      telegram = {
        enabled = true;
        dmPolicy = "pairing";
        botToken = "8540097525:AAEtI1GiIXoahua2iwuJNobIRhBxXg6lQY0";
        groupPolicy = "allowlist";
        streamMode = "partial";
      };
    } else {};
    gateway = if cfg.isMaster then {
      port = cfg.gatewayPort;
      bind = "lan";
      mode = "local";
      auth = { mode = "token"; token = "dbb9006cbbc79469bb412207e3dec142d3d17a7a47d14ca7"; };
    } else {
      port = cfg.gatewayPort;
      bind = "loopback";
      mode = "local";
    };
    skills = { install = { nodeManager = "npm"; }; };
    plugins = if cfg.isMaster then {
      allow = [
        "qwen-portal-auth"
        "whatsapp"
        "telegram"
        "discord"
        "slack"
        "signal"
        "googlechat"
        "nostr"
        "web"
        "email"
        "calendar"
        "memory"
        "filesystem"
        "browser"
        "docker"
        "kubernetes"
        "aws"
        "gcp"
        "azure"
        "github"
        "gitlab"
        "bitbucket"
        "jira"
        "trello"
        "asana"
        "linear"
      ];
      entries = {
        "qwen-portal-auth" = { enabled = true; };
        "whatsapp" = { enabled = true; };
        "telegram" = { enabled = true; };
        "discord" = { enabled = true; };
        "slack" = { enabled = true; };
        "signal" = { enabled = true; };
        "googlechat" = { enabled = true; };
        "nostr" = { enabled = true; };
        "web" = { enabled = true; };
        "email" = { enabled = true; };
        "calendar" = { enabled = true; };
        "memory" = { enabled = true; };
        "filesystem" = { enabled = true; };
        "browser" = { enabled = true; };
        "docker" = { enabled = true; };
        "kubernetes" = { enabled = true; };
        "aws" = { enabled = true; };
        "gcp" = { enabled = true; };
        "azure" = { enabled = true; };
        "github" = { enabled = true; };
        "gitlab" = { enabled = true; };
        "bitbucket" = { enabled = true; };
        "jira" = { enabled = true; };
        "trello" = { enabled = true; };
        "asana" = { enabled = true; };
        "linear" = { enabled = true; };
      };
    } else {
      allow = [];
      entries = {};
    };
  });
in
{
  options.programs.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI assistant";
    
    nodeName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Name of this node in the OpenClaw cluster";
    };
    
    gatewayPort = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "Port for OpenClaw gateway";
    };
    
    isMaster = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this node is the master/coordinator";
    };
    
    masterHost = lib.mkOption {
      type = lib.types.str;
      default = "100.81.182.5";
      description = "Tailscale IP address of the master node (for slave nodes)";
    };
    
    masterPort = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "Port of the master node gateway";
    };
    
    masterToken = lib.mkOption {
      type = lib.types.str;
      default = "dbb9006cbbc79469bb412207e3dec142d3d17a7a47d14ca7";
      description = "Auth token for connecting to master node";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create OpenClaw configuration file (master only)
    home-manager.users.j_kro = {
      home.file = {
        ".openclaw/openclaw.json" = lib.mkIf cfg.isMaster {
          source = openclawConfig;
          force = true;
        };
        ".npmrc" = {
          text = ''
            prefix=~/.npm-packages
          '';
          force = true;
        };
      };
      
      home.packages = [
        # OpenClaw CLI
        (pkgs.writeShellScriptBin "openclaw" ''
          exec ${pkgs.nodejs_22}/bin/npx openclaw "$@"
        '')
        
        # ClawdHub CLI
        (pkgs.writeShellScriptBin "clawdhub" ''
          exec ${pkgs.nodejs_22}/bin/npx clawdhub "$@"
        '')
        
        # Bird (Twitter/X CLI)
        (pkgs.writeShellScriptBin "bird" ''
          exec ${pkgs.nodejs_22}/bin/npx @steipete/bird "$@"
        '')
        
        # Summarize (content summarizer)
        (pkgs.writeShellScriptBin "summarize" ''
          exec ${pkgs.nodejs_22}/bin/npx @steipete/summarize "$@"
        '')
        
        # Camsnap (RTSP camera)
        (pkgs.writeShellScriptBin "camsnap" ''
          exec ${pkgs.nodejs_22}/bin/npx @steipete/camsnap "$@"
        '')
      ];
    };

    # Install dependencies
    environment.systemPackages = with pkgs; [
      nodejs_22
      go
      bun
      git
      curl
      jq
      _1password-cli
      himalaya
      spotify-player
      gh  # GitHub CLI
      yt-dlp  # YouTube downloader for summarize skill
      ffmpeg  # Video processing for video-frames skill
      tesseract  # OCR for slides
      imagemagick  # Image processing
    ];

    # Open firewall for OpenClaw gateway on master node
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.isMaster [ cfg.gatewayPort ];
    
    # Allow outgoing connections from slave nodes to master
    networking.firewall.extraCommands = lib.mkIf (!cfg.isMaster) ''
      # Allow OpenClaw client connections to master
      iptables -A OUTPUT -p tcp --dport ${toString cfg.masterPort} -d ${cfg.masterHost} -j ACCEPT
    '';
  };
}
