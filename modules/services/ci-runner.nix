{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.ci-runner;
  runnersCfg = config.services.ci-runners;

  # Shared per-runner fragment builder. `svcName` / `setupSvcName` are the
  # systemd unit names so the legacy single instance keeps its historical
  # names (github-actions-runner[.service] / -setup) while multi-instance
  # runners get name-suffixed units.
  mkRunner = {
    name,
    user,
    repo,
    tokenFile,
    patFile,
    autoStart,
    labels,
    extraLabels,
    svcName,
    setupSvcName,
    memoryHigh,
    memoryMax,
  }: let
    runnerHome = "/var/lib/${user}";
    # Build script fragments conditionally to avoid null interpolation
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
    allLabels = concatStringsSep "," (labels ++ extraLabels);
    # GitHub runner display name — must be unique per repo/host.
    runnerName = "${config.networking.hostName}-${name}";
  in {
    users.groups.${user} = {};
    users.users.${user} = {
      isSystemUser = true;
      group = user;
      description = "GitHub Actions runner (${name})";
      home = runnerHome;
      createHome = true;
      # Shell for the runner's step execution (GitHub resets PATH per-step to a
      # minimal FHS set; without a real login shell here, `sh` resolves to nothing).
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
        # NixOS has no FHS /usr/bin/sh. Force a PATH that includes the Nix store
        # profile bin so `sh`/`bash`/`git`/`nix` resolve when GitHub resets PATH
        # at step-exec time (root cause of 'sh: command not found' startup_failure).
        Environment = [
          "PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin:${runnerHome}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
          "RUNNER_ROOT=${runnerHome}"
          "LANG=C.UTF-8"
        ];
        ProtectSystem = "strict";
        # Keep /run/current-system, the nix store, and sops secrets visible +
        # executable under ProtectSystem=strict so steps can run shells and `nix`.
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
        # Issue #474: soft cgroup guard against runaway trusted jobs. Heavy
        # compilation itself runs inside nix-daemon's cgroup, so this is a
        # protective ceiling for the runner's own eval/shell steps, not a
        # throttle on the build farm. Per-instance so a lightweight second
        # runner (e.g. quill pnpm/tsc CI) can carry a lower ceiling than the
        # nix-config builder runner.
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
        # Always re-register: wipe any stale config so config.sh can run fresh
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

  config = lib.mkMerge [
    (lib.mkIf config.services.ci-runner.enable (mkRunner {
      name = "runner";
      user = config.services.ci-runner.user;
      repo = config.services.ci-runner.repo;
      tokenFile = config.services.ci-runner.tokenFile;
      patFile = config.services.ci-runner.patFile;
      autoStart = config.services.ci-runner.autoStart;
      labels = config.services.ci-runner.labels;
      extraLabels = config.services.ci-runner.extraLabels;
      svcName = "github-actions-runner";
      setupSvcName = "github-actions-runner-setup";
      memoryHigh = config.services.ci-runner.memoryHigh;
      memoryMax = config.services.ci-runner.memoryMax;
    }))
    (lib.mkIf config.services.ci-runners.enable (lib.mkMerge (lib.mapAttrsToList (name: inst:
      mkRunner {
        inherit name;
        user = inst.user;
        repo = inst.repo;
        tokenFile = inst.tokenFile;
        patFile = inst.patFile;
        autoStart = inst.autoStart;
        labels = inst.labels;
        extraLabels = inst.extraLabels;
        svcName = "github-actions-runner-${name}";
        setupSvcName = "github-actions-runner-setup-${name}";
        memoryHigh = inst.memoryHigh;
        memoryMax = inst.memoryMax;
      }
    ) config.services.ci-runners.instances)))
    (lib.mkIf (config.services.ci-runner.enable || config.services.ci-runners.enable) {
      environment.systemPackages = [
        pkgs.bash
        pkgs.git
        pkgs.nix
        pkgs.coreutils
        pkgs.gnused
        pkgs.gnugrep
        pkgs.gnutar
        pkgs.gzip
        pkgs.findutils
        pkgs.diffutils
        pkgs.curl
        pkgs.jq
        # cachix-action uses the runner's system PATH after its best-effort
        # nix-env install. Provision it declaratively so the action is reliable
        # on NixOS, where the runner does not inherit a user login profile.
        pkgs.cachix
        pkgs.gh
        pkgs.github-runner
      ];
    })
  ];
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
    memoryHigh = mkOption {
      type = types.str;
      default = "32G";
      description = "MemoryHigh cgroup limit for this runner (see Issue #474)";
    };
    memoryMax = mkOption {
      type = types.str;
      default = "40G";
      description = "MemoryMax cgroup limit for this runner (see Issue #474)";
    };
  };

  options.services.ci-runners = {
    enable = mkEnableOption "GitHub Actions self-hosted runners (multi-instance)";
    instances = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          user = mkOption {
            type = types.str;
            default = "runner";
            description = "User to run the runner as";
          };
          repo = mkOption {
            type = types.str;
            example = "username/some-repo";
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
          memoryHigh = mkOption {
            type = types.str;
            default = "16G";
            description = "MemoryHigh cgroup limit for this runner";
          };
          memoryMax = mkOption {
            type = types.str;
            default = "24G";
            description = "MemoryMax cgroup limit for this runner";
          };
        };
      });
      default = {};
      description = "Additional per-repo GitHub Actions runners (each gets its own systemd unit + user).";
    };
  };

}
