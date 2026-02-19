# GitHub Actions Self-Hosted Runner Service
# Configures a self-hosted runner for CI/CD deployments
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.github-actions-runner;

  # Fetch runner binary
  runner-version = "2.321.0";
  runner-src = pkgs.fetchurl {
    url = "https://github.com/actions/runner/releases/download/v${runner-version}/actions-runner-linux-x64-${runner-version}.tar.gz";
    sha256 = "17m248brzj4yai6z093bhs7w0fs5zccl9r7v2rmj7mx4wdyblims";
  };
in {
  options.services.github-actions-runner = with lib; {
    enable = lib.mkEnableOption "GitHub Actions self-hosted runner";

    user = lib.mkOption {
      type = types.str;
      default = "actions-runner";
      description = "User account to run the runner service";
    };

    group = lib.mkOption {
      type = types.str;
      default = "actions-runner";
      description = "Group for the runner service";
    };

    home = lib.mkOption {
      type = types.path;
      default = "/var/lib/github-runner";
      description = "Home directory for the runner user";
    };

    url = lib.mkOption {
      type = types.str;
      example = "https://github.com/owner/repo";
      description = "GitHub repository URL";
    };

    token = lib.mkOption {
      type = types.str;
      description = "Runner registration token (get from repo settings/actions/runners)";
    };

    name = lib.mkOption {
      type = types.str;
      default = config.networking.hostName or "nixos-runner";
      description = "Runner name";
    };

    labels = lib.mkOption {
      type = types.listOf types.str;
      default = ["self-hosted" "Linux" "x64"];
      description = "Runner labels for job routing";
    };
  };

  config = lib.mkIf cfg.enable {
    # User and group
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "GitHub Actions runner service";
      home = cfg.home;
      createHome = true;
    };

    users.groups.${cfg.group} = {};

    # Runner installation and configuration
    systemd.services.github-actions-runner-setup = {
      description = "Setup GitHub Actions Runner";
      wantedBy = ["multi-user.target"];
      before = ["github-actions-runner.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";

        ExecStart = pkgs.writeShellScript "github-actions-runner-setup" ''
          set -euo pipefail

          # Create directory structure
          mkdir -p ${cfg.home}
          chown ${cfg.user}:${cfg.group} ${cfg.home}

          # Extract runner if not already done
          if [[ ! -d ${cfg.home}/bin ]]; then
            echo "Extracting GitHub Actions runner..."
            tar -xzf ${runner-src} -C ${cfg.home}
            chown -R ${cfg.user}:${cfg.group} ${cfg.home}
          fi

          # Configure runner if not configured
          if [[ ! -f ${cfg.home}/.runner ]]; then
            echo "Configuring GitHub Actions runner..."
            cd ${cfg.home}
            su - ${cfg.user} -c '${cfg.home}/config.sh \
              --url ${cfg.url} \
              --token ${cfg.token} \
              --name ${cfg.name} \
              --labels ${builtins.concatStringsSep "," cfg.labels} \
              --work ${cfg.home}/_work'
          fi
        '';
      };
    };

    # Runner service
    systemd.services.github-actions-runner = {
      description = "GitHub Actions Runner";
      after = ["network-online.target" "github-actions-runner-setup.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      environment = {
        HOME = cfg.home;
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.home;

        # Service management
        Type = "simple";
        ExecStart = "${cfg.home}/bin/run.sh";
        Restart = "always";
        RestartSec = 10;

        # Security
        PrivateTmp = true;
        NoNewPrivileges = false; # Runner needs to spawn processes
        ProtectSystem = "strict";
        ProtectHome = false; # Needs access to runner home
        ReadWritePaths = [cfg.home];

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "actions-runner";
      };
    };
  };
}
