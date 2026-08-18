# Per-repo GitHub Actions runner generator — FUNCTION, not a NixOS module.
#
# WHY NOT A MODULE: any module whose `config` output reads
# `config.services.ci-runners` recurses under colmena's config.deployment
# extraction (2026-08-13). This function returns a plain config fragment
# (users + systemd units) built from a LITERAL instances arg; the host
# merges it with `//`. No config self-read, no recursion.
#
# Usage in hosts/<host>/services.nix:
#   let ciRunners = import ../../modules/services/ci-runners.nix { inherit lib pkgs; };
#   in (ciRunners { instances = { quill = { ... }; }; }) // { ...rest of config... }
{
  lib,
  pkgs,
}: {instances ? {}}: let
  mkRunner = name: inst: let
    user = inst.user or "runner";
    inherit (inst) repo;
    tokenFile = inst.tokenFile or null;
    patFile = inst.patFile or null;
    autoStart = inst.autoStart or false;
    # Use the node20-compatible runner package from the overlay so legacy
    # node20-based actions (e.g. codeql-action v3) can start on this host.
    runnerPkg = pkgs.github-runner-with-node20 or pkgs.github-runner;
    labels = inst.labels or ["nixos"];
    extraLabels = inst.extraLabels or [];
    memoryHigh = inst.memoryHigh or "16G";
    memoryMax = inst.memoryMax or "24G";
    runnerHome = "/var/lib/${user}";
    svcName = "github-actions-runner-${name}";
    setupSvcName = "github-actions-runner-setup-${name}";
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
          -H "Authorization: Bearer $PAT" \
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
    displayName = inst.runnerName or null;
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

    # Toolchain the workflows need on PATH (mirrors the legacy ci-runner.nix
    # provision). The runner process gets NO login shell, so steps resolve
    # commands from the system profile only. cachix-action pins
    # cachixBin=/run/current-system/sw/bin/cachix in every workflow — without
    # it the action fails instantly on the runner host.
    environment.systemPackages = [
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
      pkgs.cachix
      pkgs.gh
    ];

    systemd.services.${svcName} = lib.mkIf autoStart {
      description = "GitHub Actions Self-Hosted Runner (${name})";
      after = ["network-online.target" "${setupSvcName}.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = user;
        WorkingDirectory = runnerHome;
        # github-runner-with-node20 (overlay): ships node20 -> node24 symlink so
        # legacy node20 actions (codeql upload-sarif v3 etc.) resolve their runtime.
        ExecStart = "${runnerPkg}/bin/Runner.Listener run";
        ExecStop = "/bin/kill -INT $MAINPID";
        Restart = "always";
        RestartSec = "10s";
        Environment = [
          "PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin:${runnerHome}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
          "RUNNER_ROOT=${runnerHome}"
          # Explicit HOME so action shells (deploy workflows writing ~/.ssh,
          # venvs, caches) resolve the runner home instead of a broken '~'
          # under ProtectSystem=strict (2026-08-14: site-agency deploy's
          # ~/.ssh key write failed — 'Permission denied' — without it).
          "HOME=${runnerHome}"
          "LANG=C.UTF-8"
          # NIX_PATH so steps that use `import <nixpkgs>` (Test Suite's
          # nix-instantiate --arg pkgs) resolve nixpkgs. The runner process
          # does NOT get a login shell, so /etc/profile's NIX_PATH never
          # materializes; without this every such step exits 1 instantly
          # under the default `bash -e` step shell (2026-08-15).
          "NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos:nixos-config=/etc/nixos/configuration.nix:/nix/var/nix/profiles/per-user/root/channels"
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
      # coreutils for the PAT-ready poll loop (seq/sleep) below.
      path = [pkgs.coreutils pkgs.curl pkgs.jq runnerPkg];
      script = ''
        # Wait for the registration secret (PAT token file) to mount before
        # registering. A failed oneshot does NOT auto-retry when the secret
        # appears late (e.g. secretspec-creds mounts after this unit boots),
        # so the runner stays offline indefinitely with no listener. Poll up
        # to 5 min, then proceed — setup still fails loudly if the secret is
        # genuinely absent (drift / wrong wiring).
        ${
          if patFile != null
          then ''
            if [ ! -f "${patFile}" ]; then
              echo "Waiting for PAT file ${patFile} to mount (secretspec may lag boot)..."
              for i in $(seq 1 60); do
                [ -f "${patFile}" ] && break
                sleep 5
              done
            fi
            if [ ! -f "${patFile}" ]; then
              echo "ERROR: PAT file ${patFile} still missing after 5 min wait"
              exit 1
            fi
          ''
          else ""
        }
        rm -f "${runnerHome}/.runner" "${runnerHome}/.credentials" \
              "${runnerHome}/.credentials_rsaparams" \
              "${runnerHome}/.runner_migrated" \
              "${runnerHome}/.github-runner/.runner" \
              "${runnerHome}/.github-runner/.credentials" \
              "${runnerHome}/.github-runner/.credentials_rsaparams" \
              "${runnerHome}/.github-runner/.runner_migrated"
        ${getTokenCmd}
        ${runnerPkg}/bin/config.sh \
          --url "https://github.com/${repo}" \
          --token "$TOKEN" \
          --name "${displayName}" \
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
in
  lib.mkMerge (lib.mapAttrsToList mkRunner instances)
