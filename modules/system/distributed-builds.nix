{
  lib,
  config,
  pkgs,
  ...
}: let
  cachePolicy = import ../../contracts/cache-policy.nix;
  currentHost = config.networking.hostName or "unknown";
  # #309: derive from the declared user instead of hardcoding, so pure
  # cross-host evaluation does not depend on /home/j_kro existing.
  userHome = config.users.users.j_kro.home or "/home/j_kro";
in {
  nix = {
    distributedBuilds = lib.mkDefault true;

    settings = {
      builders = lib.mkForce "@/etc/nix/machines";
      builders-use-substitutes = true;
      # Keep signature verification enabled for upstream and custom caches.
      # The canonical policy supplies the corresponding trusted keys.
      require-sigs = lib.mkForce true;
      trusted-users = lib.mkForce [
        "root"
        "*"
        "@wheel"
      ];

      # Canonical upstream/specialized cache policy. Public caches are
      # preferred; cluster caches are fallback-only for intentional custom
      # derivations. See contracts/cache-policy.nix.
      substituters = lib.mkForce cachePolicy.substituters;
      trusted-public-keys = lib.mkForce cachePolicy.trustedPublicKeys;

      cores = lib.mkForce (
        if currentHost == "zephyr"
        then 2 # minimal for coordination
        else if currentHost == "nexus"
        then 12 # 3900X = 12 physical cores; full CPU for whichever derivation runs
        else if currentHost == "sentry"
        then 8 # R7 1700 = 8 physical cores; secondary builder
        else 2
      );

      max-jobs = lib.mkForce (
        # zephyr: ZERO local build capacity. It is a pure dispatcher — every
        # derivation offloads to nexus via /etc/nix/machines.
        # max-jobs=2 here was the OOM root cause: a local `nix build`/`switch`
        # fell back to 2 local jobs and (doubled) blew past 31GB. Never build
        # on zephyr.          # forge removed 2026-07-29 (GPU miner — do not interrupt).
        if currentHost == "zephyr"
        then 0
        else if currentHost == "nexus"
        then 2 # 12 cores x 2 jobs = 24 threads (SMT) — never over-sold (nix.dev manual)
        else if currentHost == "sentry"
        then 2 # 8 cores x 2 jobs = 16 threads (SMT) — never over-sold
        else 0
      );

      # Large NAR downloads were failing with curl error 92
      # (HTTP/2 PROTOCOL_ERROR / stream reset) on Cachix/CDN edges.
      # HTTP/1.1 is slower but avoids multiplexed range-transfer resets.
      http2 = false;
      http-connections = 16;
      connect-timeout = 10;
      download-attempts = 10;

      # ── Performance tuning (homelab fork, 2026-08-13) ──
      # Eval/fetch + store-DB latency knobs. Docs in Lix source:
      # lix/libstore/settings/*.md.
      #
      # Many flake inputs are unpinned git refs (home-manager, NUR, sops-nix,
      # colmena, stylix, ...). tarball-ttl (default 3600s) is how long a
      # fetched git tree is trusted before re-fetching; 24h cuts re-fetch
      # churn on repeated rebuilds. Pinned revs in flake.lock are unaffected.
      tarball-ttl = 86400;

      # NOTE: narinfo-cache-negative-ttl deliberately NOT set here —
      # nix-config.nix already sets it to 300s (5 min) because the cluster's
      # caches are flaky (curl-92, proxy timeouts): a short negative TTL lets
      # operations re-query soon after a cache recovers instead of trusting a
      # stale miss. Overriding it longer would fight that tuned behavior.
      # max-substitution-jobs also left at its default 16 — raising it
      # without also raising http-connections (tuned down for the curl-92
      # issue above) buys nothing.

      # Store-DB metadata fsync (default true) adds a sync-to-disk on every
      # build-output registration. Trade crash-robustness of /nix/var/nix/db
      # for registration throughput — only on the builder host (nexus);
      # consumers keep the safe default.
      fsync-metadata = lib.mkIf (currentHost == "nexus") false;
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
      # Builder OOM protection (nix.dev "Optimise the remote builder
      # configuration"): cap nix-daemon memory at 90% and give its build
      # children an OOMScoreAdjust of 500 so a runaway compile (CUDA/llvm
      # are the classic case) dies BEFORE nexus's k3s/AI-gateway/monitoring.
      min-free = 10 * 1024 * 1024;
      max-free = 200 * 1024 * 1024;
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    nrBuildUsers = 64;
  };

  # nix-daemon memory guard — protect builder host services from builds.
  # MemoryMax=90% + OOMScoreAdjust=500 (nix.dev "Optimise the remote builder
  # configuration"): builds are killed first, nexus (46 GB, k3s + AI gateway
  # + monitoring) survives a runaway CUDA/llvm compile.
  systemd.services.nix-daemon.serviceConfig = lib.mkIf (currentHost == "nexus" || currentHost == "sentry") {
    MemoryAccounting = true;
    MemoryMax = "90%";
    OOMScoreAdjust = 500;
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
            export CACHIX_AUTH_TOKEN="$(tr -d '\\r\\n' < /run/secrets/cachix-token)"
            ( flock 9; nice -n 19 ${pkgs.coreutils}/bin/timeout 600 ${pkgs.cachix}/bin/cachix push reverb-os $OUT_PATHS ) 9>/var/lock/cachix-push.lock >> /var/log/cachix-push.log 2>&1 &
          fi
          ;;
      esac
      # nexus is not always reachable (outage, rescue boot, reboot). Probe
      # first and NEVER let the copy decide the hook's exit status: with the
      # old `exec ... nix copy`, an unreachable nexus made every otherwise
      # successful build report a post-build-hook failure. Explicit `exit 0`
      # keeps cache-population strictly best-effort.
      if ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=3 \
           -o StrictHostKeyChecking=accept-new nexus true 2>/dev/null; then
        nice -n 19 nix copy --to ssh://j_kro@nexus \
          --substitute-on-destination $OUT_PATHS 2>/dev/null || true
      fi
    fi
    exit 0
  '';

  # ── cachix watch-store: continuous auto-push to reverb-os cachix ──
  # Safety net on top of the post-build-hook: pushes every new store path
  # as it lands (incl. substituted/cloned closures), not just locally-built
  # outputs. Runs on the cache publisher hosts (nexus/sentry); only Nexus
  # is a build executor. Zephyr never builds (max-jobs=0, RAM-constrained)
  # and Forge is the GPU miner (do not disturb). Idle-priority so it never
  # contends with builds/mining.
  systemd.services.cachix-watch-store = lib.mkIf (builtins.elem currentHost ["nexus" "sentry"]) {
    description = "Push new store paths to reverb-os cachix";
    wantedBy = ["multi-user.target"];
    # secretspec-creds materializes /run/secrets/cachix-token; ordering
    # after it avoids a boot-time token race. StartLimitBurst bounds the
    # restart loop if the token is genuinely absent (same pattern as
    # secretspec-creds.nix).
    after = ["network-online.target" "nix-daemon.service" "secretspec-creds.service"];
    wants = ["network-online.target"];
    unitConfig = {
      # A missing optional cache credential must not create a failed unit or
      # restart storm during boot/shutdown. The service is skipped until the
      # secret exists; the path unit below then starts it without a reboot.
      ConditionFileNotEmpty = "/run/secrets/cachix-token";
      StartLimitBurst = 3;
      StartLimitIntervalSec = 300;
    };
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = 30;
      Nice = 19;
      IOSchedulingPriority = 7; # idle
    };
    script = ''
      token=$(tr -d '\\r\\n' < /run/secrets/cachix-token)
      if [ -z "$token" ]; then
        echo "cachix-watch-store: token is empty — refusing to start" >&2
        exit 1
      fi
      export CACHIX_AUTH_TOKEN="$token"
      exec ${pkgs.cachix}/bin/cachix watch-store reverb-os
    '';
  };

  # SecretSpec writes this file after multi-user.target on some hosts. A path
  # unit gives the optional watcher a deterministic late-start path without
  # making cache publishing part of the boot-critical dependency graph.
  systemd.paths.cachix-watch-store = lib.mkIf (builtins.elem currentHost ["nexus" "sentry"]) {
    wantedBy = ["multi-user.target"];
    pathConfig = {
      PathExists = "/run/secrets/cachix-token";
      Unit = "cachix-watch-store.service";
    };
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
              speedFactor = 1; # non-builder / dispatch target
              supportedFeatures = [];
              mandatoryFeatures = [];
            }
            {
              hostName = "nexus";
              # Nexus is the exclusive builder and also serves Steam/VR
              # multilib closures (for example volk.i686-linux). An x86_64
              # kernel can build the i686 target, so advertise both systems
              # explicitly; without this Nix rejects the derivation before
              # the remote build starts.
              systems = ["x86_64-linux" "i686-linux"];
              sshUser = "j_kro";
              sshKey = userHome + "/.ssh/id_ed25519";
              maxJobs = 2; # sync with nix.settings.max-jobs on nexus (12 cores x 2)
              speedFactor = 10; # exclusive builder
              connectTimeout = 1;
              supportedFeatures = [
                "big-parallel"
                "kvm"
              ];
              mandatoryFeatures = [];
            }
            {
              hostName = "sentry";
              # Secondary builder (R7 1700, 8 physical cores, 31 GiB RAM).
              # ssh-ng was wedged here before at 16-job oversubscription
              # (pipe-drain NixOS/nix#5701); the new low-jobs config (2 jobs,
              # connect-timeout=1) keeps pipe pressure low, and nexus has run
              # ssh-ng fine under this config since. If it wedges again,
              # flip protocol to "ssh" (nix-store --serve, no pipe-drain path).
              # maxJobs=2 syncs with sentry's own nix.settings.max-jobs
              # (8 cores x 2 jobs = 16 SMT threads).
              protocol = "ssh-ng";
              systems = ["x86_64-linux"];
              sshUser = "j_kro";
              sshKey = userHome + "/.ssh/id_ed25519";
              maxJobs = 2;
              speedFactor = 6; # secondary — below nexus's 10
              connectTimeout = 1;
              supportedFeatures = [
                "big-parallel"
                "kvm"
              ];
              mandatoryFeatures = [];
            }
          ];
          # Nexus is the sole builder. Sentry is monitoring/inference and Forge
          # is the GPU-mining host; neither may receive Nix build jobs.
          #
          # REMOTE-ONLY, never a self-entry. When a host builds its own closure
          # (nexus via colmena apply-local, or any manual nixos-rebuild), a
          # `ssh-ng://<self>` machine entry makes nix-daemon dispatch
          # derivations back to itself over SSH; the serve session then waits
          # on store locks the local daemon already holds -> permanent deadlock
          # (observed 2026-08-08: wivrn build stalled 3600s on 'waiting for
          # lock' via ssh-ng://j_kro@nexus, even for a direct nix-store
          # --realise). Local builds use max-jobs; the machines file only ever
          # lists remote builders.
          machines = builtins.filter (m: m.hostName != currentHost) allMachines;
          formatMachine = m:
            with builtins; let
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
              # connect-timeout must be IN the machine line — ssh-ng does not
              # honor ssh_config ConnectTimeout for the builder probe, so a
              # down builder would stall every derivation for the full TCP
              # timeout (the 2026-08-06 forge stall). Nix parses it as a
              # feature token; emit it first so dead remotes fail in ~1s.
              timeoutOpt = "connect-timeout=" + toString (if m ? connectTimeout then m.connectTimeout else 1);
              optFeatures = concatStringsSep "," ([timeoutOpt] ++ m.supportedFeatures);
              mandFeatures =
                if m.mandatoryFeatures == []
                then ""
                else concatStringsSep "," m.mandatoryFeatures;
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
    # ccache dir must be WRITABLE by nixbld build users or ccache silently
    # misses every build (nixpkgs #140410). 0770 root:nixbld matches the
    # programs.ccache module's own rule.
    "d /var/cache/ccache 0770 root nixbld -"
    "f /var/log/ccache.log 0644 root root -"
    "f /var/log/cachix-push.log 0644 root root -"
  ] ++ lib.optional (currentHost == "nexus") "d /var/lib/nix-cache-key 0700 root root -";
  # The environment.variables CCACHE_* above point compilers at
  # /var/cache/ccache, but nothing wrapped the derivation with ccacheStdenv —
  # every llama.cpp patch recompiled all 967 units from scratch (30-40 min).
  # programs.ccache re-overrides the named packages with ccacheStdenv
  # (compilers wrapped by ccache); measured rebuild speedup ~89% (nixpkgs
  # PR #7082). Gated to the builder hosts (nexus/sentry): zephyr never
  # builds (max-jobs=0) and forge is the GPU miner.
  programs.ccache = lib.mkIf (builtins.elem currentHost ["nexus" "sentry"]) {
    enable = true;
    cacheDir = "/var/cache/ccache";
    owner = "root";
    group = "nixbld";
    # The unified llama.cpp is the expensive derivation (CUDA + Vulkan +
    # webui); cache its compiles so fork bumps and patch iterations become
    # near-instant rebuilds instead of full recompiles.
    packageNames = ["llama-cpp-unified" "llama-cpp-unified-vulkan"];
  };

  # ── nexus as a signed substituter ──
  # The post-build-hook above already copies built paths to nexus; making
  # nexus a trusted substituter lets zephyr/colmena PULL a path it already
  # built instead of re-dispatching it (and rebuilding its deps locally
  # first). The signing key lives on nexus (/etc/nixos/ssh or the key file
  # referenced by secret-key-files); the public half is trusted cluster-wide
  # via cache-policy.nix (nexus-cache-1 key) — see the module comment.
  nix.settings.secret-key-files = lib.mkIf (currentHost == "nexus") [
    "/var/lib/nix-cache-key/nexus-cache-1.sec"
  ];
}
