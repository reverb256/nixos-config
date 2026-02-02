# LM Studio - Local LLM Interface
# Desktop application and optional local server for running LLMs

{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.lmstudio;
  
  # Current version - check https://lmstudio.ai for updates
  lmstudioVersion = "0.3.23-3";
  lmstudioSrc = pkgs.fetchurl {
    url = "https://installers.lmstudio.ai/linux/x64/${lmstudioVersion}/LM-Studio-${lmstudioVersion}-x64.AppImage";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
  
  # Build LM Studio package from AppImage
  lmstudioPackage = pkgs.appimageTools.wrapType2 {
    pname = "lm-studio";
    version = lmstudioVersion;
    src = lmstudioSrc;
    
    extraPkgs = pkgs: with pkgs; [
      electron
      libappindicator
      libnotify
      libsecret
      xdg-utils
      zlib
      libxkbcommon
      at-spi2-atk
      at-spi2-core
      cups
      libdrm
      libxshmfence
      mesa
      nspr
      nss
      systemd
    ];
    
    # Electron sandbox requires special handling
    makeWrapperArgs = [
      "--add-flags --no-sandbox --disable-gpu-sandbox"
      "--prefix PATH : ${lib.makeBinPath [ pkgs.bash ]}"
    ];
    
    # Additional runtime dependencies
    extraInstallCommands = ''
      # Fix chrome-sandbox permissions for Electron
      chmod 4755 "$out/share/lm-studio/chrome-sandbox" 2>/dev/null || true
      
      # Create desktop entry
      mkdir -p "$out/share/applications"
      cat > "$out/share/applications/lm-studio.desktop" << 'EOF'
[Desktop Entry]
Name=LM Studio
Comment=Run LLMs locally with an easy-to-use interface
Exec=lm-studio --no-sandbox
Icon=lm-studio
Terminal=false
Type=Application
Categories=Development;Education;AI;
EOF
    '';
  };
in {
  options.services.lmstudio = {
    enable = mkEnableOption "LM Studio - Local LLM Interface";

    package = mkOption {
      type = types.package;
      default = lmstudioPackage;
      defaultText = "pkgs.lmstudio (AppImage-based)";
      description = "LM Studio package to use";
    };

    enableServer = mkOption {
      type = types.bool;
      default = false;
      description = "Enable local LLM server (OpenAI-compatible API on port 1234)";
    };

    serverPort = mkOption {
      type = types.port;
      default = 1234;
      description = "Port for local LM Studio server";
    };

    serverHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host for local LM Studio server";
    };

    modelsDir = mkOption {
      type = types.path;
      default = "${config.xdg.dataHome}/lm-studio/models";
      description = "Directory to store downloaded models";
    };
  };

  config = mkIf cfg.enable {
    # Create models directory
    systemd.tmpfiles.settings.lmstudio = {
      "${cfg.modelsDir}" = {
        d = {
          user = config.users.users.j_kro.name;
          group = config.users.users.j_kro.name;
          mode = "0755";
        };
      };
    };

    # Add LM Studio to system packages (for CLI access)
    environment.systemPackages = with pkgs; [
      cfg.package
    ];

    # Desktop entry
    environment.sessionVariables = {
      XDG_DATA_HOME = config.xdg.dataHome;
      # Required for Electron
      ELECTRON_DISABLE_SANDBOX = "1";
    };

    # Optional: Local server systemd service
    # Note: LM Studio server features depend on version - not all versions support headless server
    systemd.services.lmstudio-server = mkIf cfg.enableServer {
      description = "LM Studio Local LLM Server";
      after = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = "j_kro";
        Group = "j_kro";
        Restart = "on-failure";
        RestartSec = "10s";
        WorkingDirectory = cfg.modelsDir;
        
        # Note: LM Studio server CLI may vary by version
        # Check documentation for exact flags
        ExecStart = "${cfg.package}/bin/lm-studio serve --port ${toString cfg.serverPort} --host ${cfg.serverHost}";
        
        # Environment
        Environment = [
          "HF_HOME=${config.xdg.cacheHome}/huggingface"
          "XDG_CACHE_HOME=${config.xdg.cacheHome}"
          "ELECTRON_DISABLE_SANDBOX=1"
        ];
      };
    };

    # Firewall: only localhost access by default
    networking.firewall.interfaces.lo.allowedTCPPorts = mkIf cfg.enableServer [cfg.serverPort];
  };
}
