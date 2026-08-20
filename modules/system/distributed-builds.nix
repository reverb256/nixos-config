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
  # Single source of truth for the remote-builder topology (shared with
  # colmena.nix via lib/build-machines.nix).
  buildMachines = import ../../lib/build-machines.nix {inherit lib userHome;};
in {
  nix = {
    distributedBuilds = lib.mkDefault true;

    settings = {
      builders = lib.mkForce "@/etc/nix/machines";
      builders-use-substitutes = true;
      # Keep signature verification enabled for upstream and custom caches.
      # The canonical policy supplies the corresponding trusted keys.
      require-sigs = lib.mkForce true;
      # The canonical trust policy in nix-config.nix grants this host's
      # operator and root access to privileged daemon settings. Do not restore
      # the wildcard: it grants every local user trusted-user access to the
      # Nix daemon and its cache/configuration controls.

      # Canonical upstream/specialized cache policy. Public caches are
      # preferred; cluster caches are fallback-only for intentional custom
      # derivations. See contracts/cache-policy.nix.
      substituters = lib.mkForce cachePolicy.substituters;
      trusted-public-keys = lib.mkForce cachePolicy.trustedPublicKeys;

      cores = lib.mkForce (
              # CPU-headroom reservation. Per-host build-thread budget is
              # (max-jobs * cores) as a share of logical cores:
              #   nexus  24 logical -> 2*9 = 18 threads = 75%, 6 reserved
              #   sentry 16 logical -> 2*6 = 12 threads = 75%, 4 reserved
              #   zephyr 32 logical -> 2*8 = 16 threads = 50%, 16 reserved
              #   forge   6 logical -> 1*2 =  2 threads = 33%, 4 reserved
              # zephyr is a workstation — 16 threads for concurrent builds,
              # remaining 16 threads for desktop, gaming, gaming VMs, etc.
              # OOM was previously a llama misconfiguration; verified resolved 2026-08-13,
              # so zephyr can safely build local derivations again. (2026-08-18, j_kro)
              # forge mines on its GPUs, not its CPU: measured load 0.25 on an
              # i5-9500 with both peakminers at 100% GPU. A single 2-thread build
              # slot uses idle CPU without touching mining throughput, and the
              # nix-daemon memory guard below (MemoryMax=90%, OOMScoreAdjust=500)
              # ensures a runaway compile dies before the miners. (2026-08-19)
              if currentHost == "zephyr"
              then 8 # 50% of 32 logical; 2*8=16 threads, 16 reserved
              else if currentHost == "nexus"
              then 9 # 3900X = 24 logical; 2*9=18 threads, 25% reserved
              else if currentHost == "sentry"
              then 6 # R7 1700 = 16 logical; 2*6=12 threads (75%), 4 reserved.
                     # Raised from 4 (50%) on 2026-08-19: sentry's crashes were
                     # proven to be ENOSPC (journald watchdog timeout on a full
                     # disk), NOT CPU saturation, so the extra headroom was
                     # buying nothing. k3s control plane + Vulkan inference keep
                     # 4 threads.
              else if currentHost == "forge"
              then 0 # NO local builds: forge is the GPU miner (2x 4060). 95C under load
                     # is revenue-critical — keep CPU entirely free for k3s + miners.
              else 2
            );

      max-jobs = lib.mkForce (
              # zephyr: local build capacity re-enabled 2026-08-18. OOM root cause was a
              # llama misconfiguration that has been resolved. max-jobs=3 with cores=8
              # (75% of 32 logical) gives zephyr 24 build threads while leaving 8 for
              # desktop, gaming, and gaming VMs. derivations offload to nexus via
              # /etc/nix/machines when local capacity is saturated.
              # The former max-jobs=0 was a protective wedge while the llama issue was
              # unresolved; now that it is resolved, zephyr builds locally again.
              if currentHost == "zephyr"
              then 3 # 75% of 32 logical cores; 24 threads for builds, 8 for desktop
              else if currentHost == "nexus"
              then 2 # 12 cores x 2 jobs = 12 threads — half of SMT to prevent OOM (2026-08-16)
              else if currentHost == "sentry"
              then 2 # x cores=6 -> 12 of 16 logical threads (75%); 4 reserved
                     # for the k3s control plane and Vulkan inference
              else if currentHost == "forge"
              then 0 # NO local builds: forge is the GPU miner (2x 4060). 95C under
                     # load is revenue-critical — CPU stays fully free for miners + k3s.
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
  # configuration"): builds are killed first, the host survives a runaway
  # CUDA/llvm compile. Applies to all builder-capable hosts including zephyr
  # (local builds for desktop packages).
  systemd.services.nix-daemon.serviceConfig = {
    MemoryAccounting = true;
    MemoryHigh = "80%";
    MemoryMax = "90%";
    OOMScoreAdjust = 500;
  };

  # ── Post-build hook: auto-push completed builds ──
  # 1) reverb-os cachix (incremental — skips already-cached paths). The
  #    nix-daemon runs as root, so the token must be exported explicitly
  #    (cachix-auth caches it only for j_kro). Gated to the builder hosts
  #    (nexus/sentry) — zephyr builds locally + remote since 2026-08-18 (llama OOM root cause resolved) and forge is the GPU
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
  # outputs. Runs on the cache publisher hosts (nexus/sentry). Zephyr builds
  # locally and as a remote builder since 2026-08-18/19, but is not a cache
  # publisher (its uploads would compete with interactive desktop use), and
  # Forge is the GPU miner (do not disturb). Idle-priority so it never
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
        # Generated from lib/build-machines.nix (single source of truth).
        # REMOTE-ONLY, never a self-entry. When a host builds its own closure
        # (nexus via colmena apply-local, or any manual nixos-rebuild), a
        # `ssh-ng://<self>` machine entry makes nix-daemon dispatch
        # derivations back to itself over SSH; the serve session then waits
        # on store locks the local daemon already holds -> permanent deadlock
        # (observed 2026-08-08: wivrn build stalled 3600s on 'waiting for
        # lock' via ssh-ng://j_kro@nexus, even for a direct nix-store
        # --realise). Local builds use max-jobs; the machines file only ever
        # lists remote builders.
        text = buildMachines.machinesTextFor currentHost;
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
  # PR #7082). Gated to the cache-publishing builders (nexus/sentry); zephyr
  # builds too but keeps its disk for desktop/games, and forge is the GPU miner.
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
