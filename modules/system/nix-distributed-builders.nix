{ config, lib, pkgs, ... }:
let
  cfg = config.nix.distributedBuilds-config;
  # #309: derive from the declared user instead of hardcoding /home/j_kro.
  userHome = config.users.users.j_kro.home or "/home/j_kro";
in {
  options.nix.distributedBuilds-config = {
    enable = lib.mkEnableOption "distributed Nix builds across cluster hosts";
  };

  config = lib.mkIf cfg.enable {
    nix = {
      distributedBuilds = true;
      builders = [
        # Primary: nexus (3900X, 12c, 46GB). 12 jobs, 4 cores/job max.
        # SSH ConnectTimeout=5 keeps unreachable builders from stalling builds.
        "ssh://j_kro@nexus x86_64-linux ${userHome}/.ssh/id_ed25519 12 4 big-parallel -"

        # Secondary: sentry (R7 1700, 8c, 31GB). 8 jobs, 3 cores/job max.
        "ssh://j_kro@sentry x86_64-linux ${userHome}/.ssh/id_ed25519 8 3 big-parallel -"
      ];
      connectTimeout = 5;
    };

    environment.etc."nix/ssh-config-builders".text = ''
      Host nexus
        HostName 10.1.1.120
        User j_kro
        IdentityFile ${userHome}/.ssh/id_ed25519
        IdentitiesOnly yes
        ConnectTimeout 5
        ServerAliveInterval 5
        ServerAliveCountMax 1

      Host sentry
        HostName 10.1.1.140
        User j_kro
        IdentityFile ${userHome}/.ssh/id_ed25519
        IdentitiesOnly yes
        ConnectTimeout 5
        ServerAliveInterval 5
        ServerAliveCountMax 1
    '';
  };
}
