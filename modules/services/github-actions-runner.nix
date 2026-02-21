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
      default = "";
      description = "Runner registration token (get from repo settings/actions/runners). DEPRECATED: Use tokenFile instead for better security.";
    };

    tokenFile = lib.mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to age-encrypted token file (recommended over plain token)";
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
          set -eo pipefail

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
            # Set up PATH with necessary tools for config.sh (including ldd)
            export PATH="${pkgs.glibc.bin}/bin:${pkgs.binutils}/bin:${pkgs.coreutils}/bin:${pkgs.bash}/bin:${pkgs.util-linux}/bin:$PATH"
            # Set up library path for .NET dependencies (libstdc++, libz, etc.)
            export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.zlib.out}/lib:${pkgs.openssl.out}/lib:${pkgs.curl.out}/lib:${pkgs.icu.out}/lib:''${LD_LIBRARY_PATH:-}"
            # Get token from secret file or use plain token (deprecated)
            ${lib.optionalString (cfg.tokenFile != null) ''
            RUNNER_TOKEN=$(cat ${cfg.tokenFile})
            ''}
            ${lib.optionalString (cfg.tokenFile == null && cfg.token != "") ''
            RUNNER_TOKEN="${cfg.token}"
            ''}
            # Use sudo -u to run as the runner user with proper environment
            ${pkgs.sudo}/bin/sudo -u ${cfg.user} \
              env PATH="$PATH" LD_LIBRARY_PATH="$LD_LIBRARY_PATH" RUNNER_TOKEN="$RUNNER_TOKEN" \
              ${cfg.home}/config.sh \
              --url ${cfg.url} \
              --token "$RUNNER_TOKEN" \
              --name ${cfg.name} \
              --labels ${builtins.concatStringsSep "," cfg.labels} \
              --work ${cfg.home}/_work
          fi

          # Fix shebangs in runner scripts for NixOS compatibility
          for script in config.sh env.sh run.sh safe_sleep.sh run-helper.sh svc.sh; do
            if [[ -f ${cfg.home}/$script ]]; then
              sed -i '1s|#!/bin/bash|#!/usr/bin/env bash|' ${cfg.home}/$script
            fi
          done

          # Remove template file to avoid cp errors
          rm -f ${cfg.home}/run-helper.sh.template

          # Create wrapper script
          cat > ${cfg.home}/run-wrapper.sh << 'WRAPPER_EOF'
#!/usr/bin/env bash
# Wrapper for GitHub Actions Runner on NixOS
exec ${cfg.home}/run.sh "$@"
WRAPPER_EOF
          chmod +x ${cfg.home}/run-wrapper.sh
          chown ${cfg.user}:${cfg.group} ${cfg.home}/run-wrapper.sh
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
        LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.zlib.out}/lib:${pkgs.openssl.out}/lib:${pkgs.curl.out}/lib:${pkgs.icu.out}/lib";
        PATH = lib.mkForce "${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.glibc.bin}/bin:${pkgs.binutils}/bin";
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.home;

        # Service management
        Type = "simple";
        ExecStart = "${cfg.home}/run-wrapper.sh";
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
