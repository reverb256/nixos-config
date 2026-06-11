{
  lib,
  config,
  pkgs,
  ...
}: let
  currentHost = config.networking.hostName or "unknown";
in {
  nix = {
    distributedBuilds = lib.mkDefault false;

    settings = {
      builders = lib.mkDefault "@/etc/nix/machines";
      builders-use-substitutes = true;
      require-sigs = lib.mkForce false;
      trusted-users = lib.mkForce [
        "root"
        "*"
        "@wheel"
      ];

      substituters = lib.mkForce (
        if currentHost == "zephyr"
        then [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
          "https://cache.garnix.io"
          "https://reverb-os.cachix.org"
          "https://maplespike.cachix.org"
          "https://ezkea.cachix.org"
          "https://nix-gaming.cachix.org"
          "https://attic.xuyh0120.win/lantian"
        ]
        else [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
          "https://cache.garnix.io"
          "https://reverb-os.cachix.org"
          "https://maplespike.cachix.org"
          "https://ezkea.cachix.org"
          "https://nix-gaming.cachix.org"
          "https://attic.xuyh0120.win/lantian"
        ]
      );
      trusted-public-keys = lib.mkForce (
        if currentHost == "zephyr"
        then [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
          "reverb-os.cachix.org-1:dctKtu02bV/4fbsYbGuVVxQo9R7X6lNqUet1qj2jYzI="
          "maplespike.cachix.org-1:P6v8AHkRYDKI/xc4/OYIvMcwumkD9EafWnYERWWngYg="
          "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
          "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
          "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
        ]
        else [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
          "reverb-os.cachix.org-1:dctKtu02bV/4fbsYbGuVVxQo9R7X6lNqUet1qj2jYzI="
          "maplespike.cachix.org-1:P6v8AHkRYDKI/xc4/OYIvMcwumkD9EafWnYERWWngYg="
          "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
          "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
          "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
        ]
      );

      cores = lib.mkForce (
        if currentHost == "zephyr"
        then 4
        else if currentHost == "nexus"
        then 4
        else if currentHost == "sentry"
        then 2
        else if currentHost == "forge"
        then 2
        else 4
      );

      max-jobs = lib.mkForce (
        if currentHost == "zephyr"
        then 0 # zero local builds — offload everything to nexus/sentry
        else if currentHost == "nexus"
        then 10 # primary builder
        else if currentHost == "sentry"
        then 4 # secondary builder
        else if currentHost == "forge"
        then 3
        else 2
      );

      http-connections = 100;
      connect-timeout = 30;
      max-silent-time = 3600;
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

  programs.ssh.startAgent = true;

  systemd.services.copy-build-ssh-key = {
    description = "Copy SSH key for distributed builds";
    wantedBy = ["multi-user.target"];
    after = ["local-fs.target"];
    before = ["nix-daemon.service"];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      if [ ! -f /etc/nixos/ssh/id_ed25519 ] && [ -f /home/j_kro/.ssh/id_ed25519 ]; then
        install -m 600 /home/j_kro/.ssh/id_ed25519 /etc/nixos/ssh/id_ed25519
        install -m 644 /home/j_kro/.ssh/id_ed25519.pub /etc/nixos/ssh/id_ed25519.pub
      elif [ ! -f /etc/nixos/ssh/id_ed25519 ]; then
        echo "copy-build-ssh-key: No SSH key found, remote builds unavailable"
      fi
    '';
  };

  environment = {
    etc = {
      "ssh/ssh_config.d/50-build-machines.conf".text = ''
        Host zephyr nexus sentry
          User j_kro
          IdentityFile /etc/nixos/ssh/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          ConnectTimeout 30
      '';

      "nix/machines".text = let
        allMachines = [
          {
            hostName = "zephyr";
            system = "x86_64-linux";
            sshUser = "j_kro";
            sshKey = "/etc/nixos/ssh/id_ed25519";
            maxJobs = 0;
            speedFactor = 4;
            supportedFeatures = [
              "big-parallel"
              "kvm"
            ];
            mandatoryFeatures = [];
          }
          {
            hostName = "nexus";
            system = "x86_64-linux";
            sshUser = "j_kro";
            sshKey = "/etc/nixos/ssh/id_ed25519";
            maxJobs = 10;
            speedFactor = 5;
            supportedFeatures = [
              "big-parallel"
              "kvm"
            ];
            mandatoryFeatures = [];
          }
          {
            hostName = "sentry";
            system = "x86_64-linux";
            sshUser = "j_kro";
            sshKey = "/etc/nixos/ssh/id_ed25519";
            maxJobs = 4;
            speedFactor = 3;
            supportedFeatures = ["big-parallel"];
            mandatoryFeatures = [];
          }
        ];
        machines = builtins.filter (m: m.hostName != currentHost) allMachines;
        formatMachine = m: ''
          ssh-ng://${m.sshUser}@${m.hostName} ${m.system} ${
            if m.sshKey != null
            then m.sshKey
            else "-"
          } ${toString m.maxJobs} ${toString m.speedFactor} ${lib.concatStringsSep "," m.supportedFeatures} ${lib.concatStringsSep "," m.mandatoryFeatures}
        '';
      in
        lib.concatMapStrings formatMachine machines;
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
    "d /etc/nixos/ssh 0755 root root -"
    "d /var/cache/ccache 0755 root root -"
    "f /var/log/ccache.log 0644 root root -"
  ];
}
