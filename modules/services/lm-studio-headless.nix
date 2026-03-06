# LM Studio Headless Service
# Runs LM Studio in headless mode using the lms CLI
{ config, lib, pkgs, ... }:
let
  cfg = config.services.lm-studio-headless;
in {
  options.services.lm-studio-headless = {
    enable = lib.mkEnableOption "LM Studio headless service (lms CLI)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 1234;
      description = "Port for LM Studio API server";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address to bind to";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User to run LM Studio as";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall for the configured port";
    };

    gpuDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 1;
      description = "GPU device ID to use (null = all GPUs, 0 = 3060Ti, 1 = 3090)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Open firewall if requested
    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;

    # Systemd service for LM Studio headless mode
    systemd.services.lm-studio-headless = {
      description = "LM Studio Headless Service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = "users";
        WorkingDirectory = "/home/${cfg.user}";

        # Add lms CLI to PATH
        Environment = (
          [
            "PATH=/home/${cfg.user}/.lmstudio/bin:/run/current-system/sw/bin"
            "LMS_SERVER_HOST=${cfg.host}"
          ] ++ lib.optional (cfg.gpuDevice != null) "CUDA_VISIBLE_DEVICES=${toString cfg.gpuDevice}"
        );

        # Start the server in headless mode
        ExecStart = "/home/${cfg.user}/.lmstudio/bin/lms server start --port ${toString cfg.port} --bind ${cfg.host}";
        ExecStop = "/home/${cfg.user}/.lmstudio/bin/lms server stop";

        # Restart on failure
        Restart = "on-failure";
        RestartSec = "10s";

        # Security settings
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };
  };
}
