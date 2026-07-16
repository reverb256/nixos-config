{
  lib,
  config,
  pkgs,
  ...
}: let
  currentHost = config.networking.hostName or "unknown";
in {
  nix = {
    distributedBuilds = lib.mkDefault true;

    settings = {
      builders = lib.mkDefault "@/etc/nix/machines";
      builders-use-substitutes = true;
      require-sigs = lib.mkForce false;
      # FIX (2026-07-16): nix defaults to libcurl --speed-limit 1 --speed-time 300
      # during substituter fetches. When a NAR is streamed/extracted through a pipe
      # (common for large paths like luajit/libde265/imath/flite), throughput dips
      # below 1 byte/s and nix ABORTS the fetch -> infinite "copying path ... from
      # cache.nixos.org" stall (NixOS/nixpkgs#160289, #65015). Disabling the
      # stalled-download timeout stops the abort; the fetch then completes.
      stalled-download-timeout = lib.mkDefault 0;
      trusted-users = lib.mkForce [
        "root"
        "*"
        "@wheel"
      ];

      # NOTE (2026-07-16): only fast/reliable substituters. maplespike, reverb-os,
      # ezkea, and nix-gaming cachix mirrors are too slow (5-min "Operation too
      # slow" timeouts per request before falling through to the next cache).
      # cache.nixos.org + nix-community.cachix.org are fast and well-populated.
      # Clean build results are pushed back to nexus by the post-build-hook.
      substituters = lib.mkForce (
        if currentHost == "zephyr"
        then [
          "https://cache.nixos.org?priority=90"
          "https://nix-community.cachix.org?priority=80"
        ]
        else [
          "https://cache.nixos.org?priority=90"
          "https://nix-community.cachix.org?priority=80"
        ]
      );
      trusted-public-keys = lib.mkForce (
        if currentHost == "zephyr"
        then [
          "zephyr-cache-1:2Tqq4OUEZrz6DEXurUPrAQBjh1VoiQ0jZhrGYozHq5c="
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zybkq5CX+/rkCWyvRCYg3Fs="
          "reverb-os.cachix.org-1:dctKtu02bV/4fbsYbGuVVxQo9R7X6lNqUet1q2jYzI="
          "maplespike.cachix.org-1:P6v8AHkRYDKI/xc4/OYIvMcwumkD9EafWnYERWWngYg="
          "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
          "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
        ]
        else [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zybkq5CX+/rkCWyvRCYg3Fs="
          "reverb-os.cachix.org-1:dctKtu02bV/4fbsYbGuVVxQo9R7X6lNqUet1q2jYzI="
          "maplespike.cachix.org-1:P6v8AHkRYDKI/xc4/OYIvMcwumkD9EafWnYERWWngYg="
          "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
          "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
        ]
      );

      cores = lib.mkForce (
        if currentHost == "zephyr"
        then 2 # minimal for coordination
        else if currentHost == "nexus"
        then 16
        else if currentHost == "sentry"
        then 10
        else if currentHost == "forge"
        then 6
        else 4
      );

      max-jobs = lib.mkForce (
        # zephyr: ZERO local build capacity. It is a pure dispatcher — every
        # derivation offloads to nexus/sentry/forge via /etc/nix/machines.
        # max-jobs=2 here was the OOM root cause: a local `nix build`/`switch`
        # fell back to 2 local jobs and (doubled) blew past 31GB. Never build
        # on zephyr.
        if currentHost == "zephyr"
        then 0
        else if currentHost == "nexus"
        then 16 # primary builder — 24C/48T, 25G free; 16 leaves headroom
        else if currentHost == "sentry"
        then 10 # 16C, 20G avail; inference is VRAM-bound so RAM is safe
        else if currentHost == "forge"
        then 4
        else 4
      );

      http-connections = 100;
      connect-timeout = 30;
      max-silent-time = 14400;
      keep-build-log = true;
      log-lines = 2000;
      auto-optimise-store = true;
      extra-platforms = lib.mkBefore ["i686-linux"];
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

  # ── Post-build hook: auto-push completed builds to nexus cache ──
  nix.settings.post-build-hook = pkgs.writeShellScript "upload-to-cache" ''
  if [ -n "$OUT_PATHS" ] && [ "$BUILD_STATUS" = "success" ]; then
    exec nice -n 19 nix copy --to ssh://j_kro@nexus --substitute-on-destination $OUT_PATHS 2>/dev/null
  fi
  '';

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
      if [ ! -f /home/j_kro/.ssh/id_ed25519 ]; then
        echo "copy-build-ssh-key: WARN — No SSH key at ~/.ssh/id_ed25519; remote builds disabled" >&2
      else
        chmod 600 /home/j_kro/.ssh/id_ed25519
        echo "copy-build-ssh-key: SSH key verified"
      fi
    '';
  };

  environment = {
    etc = {
      "ssh/ssh_config.d/50-build-machines.conf".text = ''
        Host zephyr nexus sentry forge
          User j_kro
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          ConnectTimeout 30
      '';

      "nix/machines" = {
        text = let
          allMachines = [
            # zephyr removed 2026-07-15: build dispatcher only, maxJobs=0 (no local builds)
            {
              hostName = "nexus";
              systems = ["x86_64-linux" "i686-linux"];
              sshUser = "j_kro";
              sshKey = "~/.ssh/id_ed25519";
              maxJobs = 12;
              speedFactor = 10; # prioritize nexus
              supportedFeatures = [
                "big-parallel"
                "kvm"
              ];
              mandatoryFeatures = [];
            }
            {
              hostName = "sentry";
              systems = ["x86_64-linux" "i686-linux"];
              sshUser = "j_kro";
              sshKey = "~/.ssh/id_ed25519";
              maxJobs = 8;
              speedFactor = 6;
              supportedFeatures = ["big-parallel"];
              mandatoryFeatures = [];
            }
          ];
          machines = builtins.filter (m: m.hostName != currentHost) allMachines;
          formatMachine = m: with builtins;
            concatStringsSep " " [
              ("ssh-ng://" + "${m.sshUser}@${m.hostName}")
              (concatStringsSep " " m.systems)
              (if m.sshKey != null then m.sshKey else "-")
              (toString m.maxJobs)
              (toString m.speedFactor)
              (concatStringsSep "," m.supportedFeatures)
              (concatStringsSep "," m.mandatoryFeatures)
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
    "d /home/j_kro/.ssh 0700 j_kro users -"
    "d /root/.ssh 0700 root root -"
    "d /root/.ssh/sockets 0700 root root -"
    "d /etc/nixos/ssh 0755 root root -"
    "d /var/cache/ccache 0755 root root -"
    "f /var/log/ccache.log 0644 root root -"
  ];
}
