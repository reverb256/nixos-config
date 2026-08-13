# Additional per-repo GitHub Actions runners (multi-instance).
#
# Declared and consumed in the SAME module, matching the repo's proven
# pattern (direct `config.services.X` reads inside the config block — see
# modules/system/sops-secrets-registry.nix, modules/caddy-router.nix).
# The original ci-runner.nix keeps its single-instance behavior untouched.
#
# Usage:
#   services.ci-runners.instances.quill = {
#     repo = "reverb256/quill";
#     patFile = "/run/secrets/github-runner-pat";
#     autoStart = true;
#     labels = ["self-hosted" "nixos"];
#     extraLabels = ["nexus" "quill"];
#   };
{
  config,
  lib,
  pkgs,
  ...
}: let
  mkRunner = name: inst: let
    user = inst.user or "runner";
    repo = inst.repo;
    tokenFile = inst.tokenFile or null;
    patFile = inst.patFile or null;
    autoStart = inst.autoStart or false;
    labels = inst.labels or ["nixos"];
    extraLabels = inst.extraLabels or [];
    memoryHigh = inst.memoryHigh or "16G";
    memoryMax = inst.memoryMax or "24G";
    runnerHome = "/var/lib/${user}";
    svcName = "github-actions-runner-${name}";
    setupSvcName = "github-actions-runner-setup-${name}";
    runnerName = "${config.networking.hostName}-${name}";
    getTokenCmd =
      if tokenFile != null
      then ''
        TOKEN=$(cat "${tokenFile}")
        echo "Using pre-generated runner token from ${tokenFile}"
      ''
      else if patFile != null
      then ''
        echo "Generating runner registration token from PAT..."
        PAT=$(cat "${patFile}")
        API_RESPONSE=$(curl -s -X POST \
          -H "Authorization: Bearer ***" \
          -H "Accept: application/vnd.github+json" \
          "https://api.github.com/repos/${repo}/actions/runners/registration-token")
        TOKEN=$(echo "$API_RESPONSE" | jq -r '.token // empty')
        if [ -z "$TOKEN" ]; then
          echo "ERROR: Failed to generate runner token from PAT"
          echo "API response: $API_RESPONSE"
          exit 1
        fi
        echo "Successfully generated runner token"
      ''
      else ''
        echo "ERROR: Neither tokenFile nor patFile is provided/available"
        exit 1
      '';
    allLabels = lib.concatStringsSep "," (labels ++ extraLabels);
  in {
    users.groups.${user} = {};
    users.users.${user} = {
      isSystemUser = true;
      group = user;
      description = "GitHub Actions runner (${name})";
      home = runnerHome;
      createHome = true;
      shell = pkgs.bash;
    };

    systemd.services.${svcName} = lib.mkIf autoStart {
      description = "GitHub Actions Self-Hosted Runner (${name})";
      after = ["network-online.target" "${setupSvcName}.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = user;
        WorkingDirectory = runnerHome;
        ExecStart = "${pkgs.github-runner}/bin/Runner.Listener run";
        ExecStop = "/bin/kill -INT $MAINPID";
        Restart = "always";
        RestartSec = "10s";
        Environment = [
          "PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin:${runnerHome}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
          "RUNNER_ROOT=${runnerHome}"
          "LANG=C.UTF-8"
        ];
        ProtectSystem = "strict";
        BindReadOnlyPaths = [
          "/run/current-system"
          "/nix/store"
          "/run/secrets"
          "/bin"
          "/usr"
        ];
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [runnerHome];
        MemoryHigh = memoryHigh;
        MemoryMax = memoryMax;
      };
    };

    systemd.services.${setupSvcName} = {
      description = "GitHub Actions Runner Setup (${name})";
      before = ["${svcName}.service"];
      requiredBy = ["${svcName}.service"];
      path = [pkgs.curl pkgs.jq pkgs.github-runner];
      script = ''
        rm -f "${runnerHome}/.runner" "${runnerHome}/.credentials" \
              "${runnerHome}/.credentials_rsaparams" \
              "${runnerHome}/.github-runner/.runner" \
              "${runnerHome}/.github-runner/.credentials" \
              "${runnerHome}/.github-runner/.credentials_rsaparams"
        ${getTokenCmd}
        ${pkgs.github-runner}/bin/config.sh \
          --url "https://github.com/${repo}" \
          --token "$TOKEN" \
          --name "${runnerName}" \
          --labels "${allLabels}" \
          --replace \
          --unattended
        echo "Runner configured successfully"
      '';
      environment = {
        RUNNER_ROOT = runnerHome;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = user;
        WorkingDirectory = runnerHome;
      };
    };
  };
in {
  options.services.ci-runners = {
    instances = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = {};
      description = "Additional per-repo GitHub Actions runners (each gets its own systemd unit + user).";
    };
  };

  config = lib.mkIf (config.services.ci-runners.instances != {}) (
    lib.mkMerge (lib.mapAttrsToList mkRunner config.services.ci-runners.instances)
  );
}
