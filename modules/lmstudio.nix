# LM Studio 0.4.x - Local LLM Interface with Daemon Mode
# Supports separated backend (llmster daemon) and frontend (GUI)

{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.lmstudio;
  
  # LM Studio 0.4.1 - check https://lmstudio.ai/download for current version
  lmstudioVersion = "0.4.1-1";
  
  # Download URL for the AppImage (GUI frontend)
  lmstudioAppImageSrc = pkgs.fetchurl {
    url = "https://installers.lmstudio.ai/linux/x64/${lmstudioVersion}/LM-Studio-${lmstudioVersion}-x64.AppImage";
    sha256 = "1w26ib8m50ns62y1q2c5sahjczi97brl2vcyy6c6fzggmn61g3ni";
  };
  
  # Extract AppImage for headless CLI use
  lmstudio-extracted = pkgs.appimageTools.extract {
    pname = "lm-studio";
    version = lmstudioVersion;
    src = lmstudioAppImageSrc;
  };
  
  # lms CLI wrapper that uses extracted AppImage
  lmsCli = pkgs.writeShellScriptBin "lms" ''
    #!/bin/bash
    export PATH="${lmstudio-extracted}/usr/sbin:$PATH"
    export LD_LIBRARY_PATH="${lmstudio-extracted}/usr/lib:$LD_LIBRARY_PATH"
    export XDG_DATA_DIRS="${lmstudio-extracted}/usr/share:$XDG_DATA_DIRS"
    exec "${lmstudio-extracted}/resources/app/.webpack/lms" "$@"
  '';
in {
  options.services.lmstudio = {
    enable = mkEnableOption "LM Studio - Local LLM Interface (0.4.x)";

    package = mkOption {
      type = types.package;
      default = pkgs.appimageTools.wrapType2 {
        pname = "lm-studio";
        version = lmstudioVersion;
        src = lmstudioAppImageSrc;
        
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
        
        makeWrapperArgs = [
          "--add-flags --no-sandbox --disable-gpu-sandbox"
        ];
        
        extraInstallCommands = ''
          # Create desktop entry
          mkdir -p "$out/share/applications"
          cat > "$out/share/applications/lm-studio.desktop" << 'EOF'
[Desktop Entry]
Name=LM Studio
Comment=Run LLMs locally with GUI and API server
Exec=lm-studio --no-sandbox
Icon=lm-studio
Terminal=false
Type=Application
Categories=Development;Education;AI;
EOF
          chmod +x "$out/share/applications/lm-studio.desktop"
        '';
      };
      defaultText = "pkgs.lmstudio (AppImage-based)";
      description = "LM Studio GUI package";
    };

    enableDaemon = mkOption {
      type = types.bool;
      default = false;  # Requires GUI initialization for authentication in 0.4.x
      description = "Enable lmsterd daemon (headless server mode, 0.4.x feature - requires GUI run first)";
    };

    daemonPort = mkOption {
      type = types.port;
      default = 1234;
      description = "Port for LM Studio local server API";
    };

    daemonHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host for LM Studio local server";
    };

    modelsDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw/.cache/lm-studio/models";
      description = "Directory to store downloaded models";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw/.local/share/lm-studio";
      description = "LM Studio data directory (conversations, settings)";
    };
  };

  config = mkIf cfg.enable {
    # Create directories
    systemd.tmpfiles.settings.lmstudio = {
      "${cfg.modelsDir}" = {
        d = {
          user = config.users.users.j_kro.name;
          group = config.users.users.j_kro.name;
          mode = "0755";
        };
      };
      "${cfg.dataDir}" = {
        d = {
          user = config.users.users.j_kro.name;
          group = config.users.users.j_kro.name;
          mode = "0755";
        };
      };
    };

    # Add LM Studio to system packages (GUI)
    environment.systemPackages = with pkgs; [
      cfg.package
      lmsCli
    ];

    # Environment variables for LM Studio
    environment.sessionVariables = {
      ELECTRON_DISABLE_SANDBOX = "1";
      LMSTUDIO_DATA_DIR = cfg.dataDir;
    };

    # llmster daemon service (0.4.x feature - separate backend)
    # Use lms CLI tool for headless server mode
    systemd.services.lmstudio-daemon = mkIf cfg.enableDaemon {
      description = "LM Studio Local LLM Server (Headless)";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = "lobster";
        Group = "lobster";
        Restart = "on-failure";
        RestartSec = "5s";
        WorkingDirectory = cfg.dataDir;

        # Use extracted AppImage for headless server (0.4.x)
        ExecStart = "${lmsCli}/bin/lms server start --bind ${cfg.daemonHost} --port ${toString cfg.daemonPort}";

        # Environment
        Environment = [
          "HOME=/var/lib/openclaw"
          "XDG_CACHE_HOME=/var/lib/openclaw/.cache"
          "XDG_DATA_HOME=${cfg.dataDir}"
          "LMSTUDIO_DATA_DIR=${cfg.dataDir}"
          "LMSTUDIO_MODELS_DIR=${cfg.modelsDir}"
          # Disable GPU sandbox for containerized runtime
          "ELECTRON_DISABLE_SANDBOX=1"
        ];

        # Runtime directory
        RuntimeDirectory = "lm-studio";
        RuntimeDirectoryMode = "0755";
      };
    };

    # Health monitoring timer
    systemd.services.lmstudio-daemon-health = mkIf cfg.enableDaemon {
      description = "Health check for LM Studio daemon";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "lmstudio-daemon-check" ''
          set -e
          if ! curl -sf "http://${cfg.daemonHost}:${toString cfg.daemonPort}/health" >/dev/null 2>&1; then
            echo "LM Studio daemon not responding, restarting..."
            systemctl restart lmstudio-daemon.service
          fi
        '';
      };
    };

    systemd.timers.lmstudio-daemon-health = mkIf cfg.enableDaemon {
      description = "Health check for LM Studio daemon";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*:*:0/30";
        Persistent = false;
      };
    };

    # Firewall: only localhost access
    networking.firewall.interfaces.lo.allowedTCPPorts = mkIf cfg.enableDaemon [cfg.daemonPort];
  };
}
