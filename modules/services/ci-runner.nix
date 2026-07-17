{ config, lib, pkgs, ... }:
with lib; let
  cfg = config.services.ci-runner;
  runnerHome = "/var/lib/${cfg.user}";
  # Build script fragments conditionally to avoid null interpolation
  getTokenCmd = if cfg.tokenFile != null then ''
    TOKEN=$(cat "${cfg.tokenFile}")
    echo "Using pre-generated runner token from ${cfg.tokenFile}"
  '' else if cfg.patFile != null then ''
    echo "Generating runner registration token from PAT..."
    PAT=$(cat "${cfg.patFile}")
    API_RESPONSE=$(curl -s -X POST \
      -H "Authorization: Bearer $PAT" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${cfg.repo}/actions/runners/registration-token")
    TOKEN=$(echo "$API_RESPONSE" | jq -r '.token // empty')
    if [ -z "$TOKEN" ]; then
      echo "ERROR: Failed to generate runner token from PAT"
      echo "API response: $API_RESPONSE"
      exit 1
    fi
    echo "Successfully generated runner token"
  '' else ''
    echo "ERROR: Neither tokenFile nor patFile is provided/available"
    exit 1
  '';
in {
  options.services.ci-runner = {
    enable = mkEnableOption "GitHub Actions self-hosted runner";
    user = mkOption {
      type = types.str;
      default = "runner";
      description = "User to run the runner as";
    };
    repo = mkOption {
      type = types.str;
      example = "username/nixos-config";
      description = "GitHub repository (owner/repo)";
    };
    tokenFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Pre-generated runner token file (alternative to patFile)";
    };
    patFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "GitHub PAT file for auto-generating runner tokens via API";
    };
    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = "Auto-start the runner service";
    };
    labels = mkOption {
      type = types.listOf types.str;
      default = ["nixos"];
      description = "Runner labels";
    };
    extraLabels = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Host-specific extra labels";
    };
  };

  config = mkIf cfg.enable {
    users.groups.${cfg.user} = {};
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      description = "GitHub Actions runner";
      home = runnerHome;
      createHome = true;
    };

    environment.systemPackages = [pkgs.curl pkgs.jq];

    systemd.services.github-actions-runner = lib.mkIf cfg.autoStart {
      description = "GitHub Actions Self-Hosted Runner";
      after = ["network-online.target" "github-actions-runner-setup.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        WorkingDirectory = runnerHome;
        ExecStart = "${pkgs.github-runner}/bin/runsvc.sh";
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'ln -sfT node24 ${pkgs.github-runner}/lib/externals/node20'";
        Restart = "always";
        RestartSec = "10s";
        ProtectSystem = "strict";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [runnerHome]
          # The runner's externals/node20 symlink needs to point to
          # node24 (nixpkgs provides node24, not node20 as runner expects).
          (builtins.toString pkgs.github-runner + "/lib/externals")
        ];
      };
    };

    systemd.services.github-actions-runner-setup = {
      description = "GitHub Actions Runner Setup";
      before = ["github-actions-runner.service"];
      requiredBy = ["github-actions-runner.service"];
      path = [pkgs.curl pkgs.jq pkgs.github-runner];
      script = let
        allLabels = lib.concatStringsSep "," (cfg.labels ++ cfg.extraLabels);
      in ''
        if [ -f "${runnerHome}/.runner" ] || [ -f "${runnerHome}/.github-runner/.runner" ]; then
          echo "Runner already configured, skipping setup"
          exit 0
        fi
        ${getTokenCmd}
        ${pkgs.github-runner}/bin/config.sh \
          --url "https://github.com/${cfg.repo}" \
          --token "$TOKEN" \
          --name "${config.networking.hostName}-runner" \
          --labels "${allLabels}" \
          --unattended
        echo "Runner configured successfully"
      '';
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        WorkingDirectory = runnerHome;
      };
    };
  };
}
