{
  lib,
  config,
  pkgs,
  ...
}: let
  currentHost = config.networking.hostName or "unknown";
  # #309: derive from the declared user instead of hardcoding, so pure
  # cross-host evaluation does not depend on /home/j_kro existing.
  userHome = config.users.users.j_kro.home or "/home/j_kro";
  cacheRegistry = import ./nix-cache-registry.nix;
in {
  nix = {
    distributedBuilds = lib.mkDefault true;

    settings = {
      builders = lib.mkForce "@/etc/nix/machines";
      builders-use-substitutes = true;
      # Keep daemon trust explicit: users can build, but cannot redefine the
      # daemon's trust boundary through wildcard administrative access.
      # Signature enforcement remains a separate compatibility-gated follow-up.
      require-sigs = lib.mkForce false;
      trusted-users = lib.mkForce ["root" "j_kro"];

      # Identical lists on every host (zephyr/else branches were identical —
      # collapsed 2026-08-01). The zephyr-cache substituter points at zephyr's
      # local binary cache (10.1.1.110:50000), which is reachable cluster-wide.
      substituters = lib.mkForce cacheRegistry.substituters;
      trusted-public-keys = lib.mkForce cacheRegistry.trustedPublicKeys;

      cores = lib.mkForce (
        if currentHost == "zephyr"
        then 2 # minimal for coordination
        else if currentHost == "nexus"
        then 12
        else if currentHost == "sentry"
        then 8
        else if currentHost == "forge"
        then 6
        else 4
      );

      max-jobs = lib.mkForce (
        # zephyr: ZERO local build capacity. It is a pure dispatcher — every
        # derivation offloads to nexus/sentry via /etc/nix/machines.
        # max-jobs=2 here was the OOM root cause: a local `nix build`/`switch`
        # fell back to 2 local jobs and (doubled) blew past 31GB. Never build
        # on zephyr.
        # forge removed 2026-07-29 (GPU miner — do not interrupt).
        if currentHost == "zephyr"
        then 0
        else if currentHost == "nexus"
        then 12 # primary builder — 12C/24T, binary cache host
        else if currentHost == "sentry"
        then 8
        else 4
      );

      # Large NAR downloads were failing with curl error 92
      # (HTTP/2 PROTOCOL_ERROR / stream reset) on Cachix/CDN edges.
      # HTTP/1.1 is slower but avoids multiplexed range-transfer resets.
      http2 = false;
      http-connections = 16;
      connect-timeout = 10;
      download-attempts = 10;
      max-silent-time = 3600;
      keep-build-log = true;
      log-lines = 2000;
      auto-optimise-store = true;
      # CRITICAL (2026-08-03): sandbox MUST be true. With sandbox=false,
      # Flutter/AOT packages (localsend) embed their build temp dir in binary
      # RPATHs -> "forbidden references" -> toplevel build fails. The
      # common-host-defaults.nix comment documents this; nexus had sandbox=false
      # in /etc/nix/nix.conf, which broke the zephyr deploy build.
      sandbox = lib.mkForce true;
      sandbox-fallback = lib.mkForce true;
      extra-sandbox-paths = [
        "/var/cache/ccache"
      ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # ── Post-build hook: auto-push completed builds ──
  # 1) reverb-os cachix (incremental — skips already-cached paths). The
  #    nix-daemon runs as root, so the token must be exported explicitly
  #    (cachix-auth caches it only for j_kro). Gated to the builder hosts
  #    (nexus/sentry) — zephyr never builds locally and forge is the GPU
  #    miner (do not disturb). Runs BACKGROUNDED (flock-serialized) so a
  #    slow WAN upload never blocks nix-daemon's next build; failures are
  #    logged to /var/log/cachix-push.log instead of being swallowed.
  # 2) nexus local store (fast LAN cache for cluster rebuilds).
  nix.settings.post-build-hook = pkgs.writeShellScript "upload-to-cache" ''
    if [ -n "$OUT_PATHS" ] && [ "$BUILD_STATUS" = "success" ]; then
      case "$(hostname)" in
        nexus|sentry)
          if [ -r /run/secrets/cachix-token ]; then
            export CACHIX_AUTH_TOKEN="$(cat /run/secrets/cachix-token)"
            ( flock 9; nice -n 19 ${pkgs.coreutils}/bin/timeout 600 ${pkgs.cachix}/bin/cachix push reverb-os $OUT_PATHS ) 9>/var/lock/cachix-push.lock >> /var/log/cachix-push.log 2>&1 &
          fi
          ;;
      esac
      exec nice -n 19 nix copy --to ssh://j_kro@nexus --substitute-on-destination $OUT_PATHS 2>/dev/null
    fi
  '';

  # ── cachix watch-store: continuous auto-push to reverb-os cachix ──
  # Safety net on top of the post-build-hook: pushes every new store path
  # as it lands (incl. substituted/cloned closures), not just locally-built
  # outputs. Runs only on the builder hosts (nexus/sentry) — zephyr never
  # builds (max-jobs=0, RAM-constrained) and forge is the GPU miner (do not
  # disturb). Idle-priority so it never contends with builds/mining.
  systemd.services.cachix-watch-store = lib.mkIf (builtins.elem currentHost ["nexus" "sentry"]) {
    description = "Push new store paths to reverb-os cachix";
    wantedBy = ["multi-user.target"];
    # secretspec-creds materializes /run/secrets/cachix-token; ordering
    # after it avoids a boot-time token race. StartLimitBurst bounds the
    # restart loop if the token is genuinely absent (same pattern as
    # secretspec-creds.nix).
    after = ["network-online.target" "nix-daemon.service" "secretspec-creds.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = 30;
      StartLimitBurst = 3;
      StartLimitIntervalSec = 300;
      Nice = 19;
      IOSchedulingPriority = 7; # idle
    };
    script = ''
      if [ ! -r /run/secrets/cachix-token ]; then
        echo "cachix-watch-store: token missing at /run/secrets/cachix-token — staying down" >&2
        exit 1
      fi
      export CACHIX_AUTH_TOKEN="$(cat /run/secrets/cachix-token)"
      exec ${pkgs.cachix}/bin/cachix watch-store reverb-os
    '';
  };

  programs.ssh.startAgent = true;

  systemd.services.copy-build-ssh-key = {
    description = "Ensure SSH key exists for distributed builds";
    wantedBy = ["multi-user.target"];
    after = ["local-fs.target"];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      # Non-fatal: warn on missing key but do NOT block nix-daemon.
      # Missing key = remote builds unavailable, local builds (maxJobs) still work.
      if [ ! -f ${userHome}/.ssh/id_ed25519 ]; then
        echo "copy-build-ssh-key: WARN — No SSH key at ~/.ssh/id_ed25519; remote builds disabled" >&2
      else
        chmod 600 ${userHome}/.ssh/id_ed25519
        echo "copy-build-ssh-key: SSH key verified"
      fi
    '';
  };

  environment = {
    etc = {
      "ssh/ssh_config.d/50-build-machines.conf".text = ''
        Host zephyr
          HostName 10.1.1.110
          User j_kro
          IdentityFile ${userHome}/.ssh/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          ConnectTimeout 5
          ServerAliveInterval 5
          ServerAliveCountMax 1

        Host nexus
          HostName 10.1.1.120
          User j_kro
          IdentityFile ${userHome}/.ssh/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          ConnectTimeout 5
          ServerAliveInterval 5
          ServerAliveCountMax 1

        Host forge
          HostName 10.1.1.130
          User j_kro
          IdentityFile ${userHome}/.ssh/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          ConnectTimeout 5
          ServerAliveInterval 5
          ServerAliveCountMax 1

        Host sentry
          HostName 10.1.1.140
          User j_kro
          IdentityFile ${userHome}/.ssh/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          ConnectTimeout 5
          ServerAliveInterval 5
          ServerAliveCountMax 1
      '';

      "nix/machines" = {
        text = let
          allMachines = [
            {
              hostName = "zephyr";
              systems = ["x86_64-linux"];
              sshUser = "j_kro";
              sshKey = userHome + "/.ssh/id_ed25519";
              maxJobs = 0;
              speedFactor = 1; # deprioritize zephyr
              supportedFeatures = [];
              mandatoryFeatures = [];
            }
            {
              hostName = "nexus";
              systems = ["x86_64-linux"];
              sshUser = "j_kro";
              sshKey = userHome + "/.ssh/id_ed25519";
              maxJobs = 12;
              speedFactor = 10; # prioritize nexus
              connectTimeout = 1;
              supportedFeatures = [
                "big-parallel"
                "kvm"
              ];
              mandatoryFeatures = [];
            }
            {
              hostName = "sentry";
              systems = ["x86_64-linux"];
              sshUser = "j_kro";
              sshKey = userHome + "/.ssh/id_ed25519";
              maxJobs = 8;
              speedFactor = 6;
              connectTimeout = 1;
              # ssh:// avoids NixOS/nix#5701 pipe-draining deadlock (ssh-ng stalls when
              # build-remote writes progress logs faster than the parent drains the pipe).
              protocol = "ssh";
              supportedFeatures = ["big-parallel"];
              mandatoryFeatures = [];
            }
          ];
          # 2026-07-29: forge (i5-9500, 6c) was previously a fallback builder.
          # REMOVED — forge is the GPU miner host, must NOT be interrupted by
          # distributed build jobs. Source comments confirm: 2x 4060s running
          # peakminer full-time, OOM protection in place. Adding build load
          # risks GPU contention or OOM-killing the miners.
          machines = builtins.filter (m: m.hostName != currentHost) allMachines;
          formatMachine = m: with builtins; let
            # Join ALL systems with commas so the nix builder line advertises
            # the supported x86_64-linux target.
            allSystems = lib.concatStringsSep "," m.systems;
            # Nix's machine parser (libstore/machines.cc) reads positions
            # strictly as: URL systemTypes(comma-joined) sshKey maxJobs
            # speedFactor supportedFeatures mandatoryFeatures. Earlier this
            # function emitted space-separated systems + a tilde key path
            # (`URL x86_64-linux ~/.ssh/...`), which pushed the
            # sshKey into Nix's maxJobs slot and triggered
            # `error: bad machine specification: failed to convert column
            # #3 ... to 'unsigned int'` (2026-07-27 cluster-fix-batch,
            # confirmed live 2026-08-01 on nexus's deployed machines file).
            # Order corrected below; trailing empty `mandatoryFeatures`
            # suppressed to avoid a trailing-empty column.
            # Connection timing is controlled by Nix's global
            # `connect-timeout` setting and the SSH config above. Keep this
            # field limited to actual machine capability tags.
            optFeatures = concatStringsSep "," m.supportedFeatures;
            mandFeatures =
              if m.mandatoryFeatures == [ ]
              then "" else concatStringsSep "," m.mandatoryFeatures;
          in
            concatStringsSep " " [
              ("${m.protocol or "ssh-ng"}://" + "${m.sshUser}@${m.hostName}")
              allSystems
              (
                if m.sshKey != null
                then m.sshKey
                else "-"
              )
              (toString m.maxJobs)
              (toString m.speedFactor)
              optFeatures
              mandFeatures
            ];
        in
          lib.concatStringsSep "\n" (map formatMachine machines) + "\n";
      };
    };

    variables = {
      CCACHE_DIR = "/var/cache/ccache";
      CCACHE_SIZE = "20G";
      CCACHE_COMPRESS = "1";
      CCACHE_COMPRESSLEVEL = "6";
      CCACHE_MAXFILES = "1000000";
      CCACHE_DIRLEVELS = "3";
      CCACHE_LOGFILE = "/var/log/ccache.log";
    };

    systemPackages = with pkgs; [ccache];
  };

  systemd.tmpfiles.rules = [
    "d ${userHome}/.ssh 0700 j_kro users -"
    "d /root/.ssh 0700 root root -"
    "d /root/.ssh/sockets 0700 root root -"
    "d /etc/nixos/ssh 0755 root root -"
    "d /var/cache/ccache 0755 root root -"
    "f /var/log/ccache.log 0644 root root -"
    "f /var/log/cachix-push.log 0644 root root -"
  ];
}
