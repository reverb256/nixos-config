{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.openclaw;
in
{
  options.programs.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI assistant";
    
    documents = lib.mkOption {
      type = lib.types.path;
      default = ./../home/openclaw-docs;
      description = "Path to OpenClaw documents directory (AGENTS.md, SOUL.md, TOOLS.md)";
    };
    
    telegramTokenFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/agenix/openclaw-telegram-token";
      description = "Path to Telegram bot token file (Agenix encrypted)";
    };
    
    model = lib.mkOption {
      type = lib.types.str;
      default = "llama3.2:3b";
      description = "Default Ollama model to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # Import the nix-openclaw Home Manager module
    home-manager.users.j_kro = { config, ... }: {
      imports = [ inputs.nix-openclaw.homeManagerModules.openclaw ];
      
      programs.openclaw = {
        enable = true;
        
        # Documents directory
        documents = cfg.documents;
        
        # Enable ALL first-party plugins on ALL hosts
        firstParty = {
          summarize.enable = true;
          peekaboo.enable = true;
          oracle.enable = true;
          poltergeist.enable = true;
          sag.enable = true;
          camsnap.enable = true;
          gogcli.enable = true;
          bird.enable = true;
          sonoscli.enable = true;
          imsg.enable = true;
        };
        
        # Configure Telegram provider
        providers.telegram = {
          enable = true;
          botTokenFile = cfg.telegramTokenFile;
          allowFrom = [ ]; # Will be configured per-host
        };
        
        # Configure default model for Ollama
        defaults = {
          model = "ollama/${cfg.model}";
          thinkingDefault = "medium";
        };
        
        # Systemd user service (enabled by default)
        systemd.enable = true;
      };
    };
    
    # Ensure required packages are available
    environment.systemPackages = with pkgs; [
      jq
      curl
    ];
  };
}
