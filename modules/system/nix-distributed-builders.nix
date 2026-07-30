{ config, lib, pkgs, ... }:
let
  cfg = config.nix.distributedBuilds-config;
in {
  options.nix.distributedBuilds-config = {
    enable = lib.mkEnableOption "distributed Nix builds across cluster hosts";
  };

  config = lib.mkIf cfg.enable {
    nix = {
      distributedBuilds = true;
      builders = [
        # Primary: nexus (3900X, 12c, 46GB). 12 jobs, 4 cores/job max.
        # ConnectTimeout=0 means immediate fail if unreachable.
        "ssh://j_kro@nexus x86_64-linux - 12 4 nix-store,max-jobs=12,big-parallel,ssh-config=/etc/nix/ssh-config-builders"

        # Secondary: sentry (R7 1700, 8c, 31GB). 8 jobs, 3 cores/job max.
        "ssh://j_kro@sentry x86_64-linux - 8 3 nix-store,max-jobs=8,big-parallel,ssh-config=/etc/nix/ssh-config-builders"
      ];
      connectTimeout = 5;
    };

    environment.etc."nix/ssh-config-builders".text = ''
      Host nexus
        HostName 10.1.1.130
        User j_kro
        IdentityFile ~/.ssh/id_ed25519
        IdentitiesOnly yes
        ConnectTimeout 0
        ServerAliveInterval 5
        ServerAliveCountMax 1

      Host sentry
        HostName 10.1.1.120
        User j_kro
        IdentityFile ~/.ssh/id_ed25519
        IdentitiesOnly yes
        ConnectTimeout 0
        ServerAliveInterval 5
        ServerAliveCountMax 1
    '';
  };
}
