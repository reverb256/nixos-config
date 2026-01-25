{
  meta = {
    nixpkgs = import <nixpkgs> {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
  };

  nodes = {
    nexus = {
      pkgs,
      ...
    }: {
      imports = [
        ./configuration.nix
        ./hosts/nexus/configuration.nix
      ];

      deployment = {
        targetHost = "10.1.1.120";
        targetUser = "root";
      };

      # Mining configuration with 12 threads for nexus
      services.mining = {
        enable = true;
        cpu = {
          package = pkgs.xmrig;
          enable = true;
          threads = 12;
          settings = {
            "donate-level" = 0;
            "pools" = [
              {
                url = "pool.supportxmr.com:443";
                user = "46i1bqJjhdSAqW5bMRK1JqcUKnrP8sYfZhCJBMGftGjnqKxLB4ymwA2mKu5UzVR2EokSf3TsHCHBEhFqnLmoN6x52fKB2hJ";
                pass = "nexus";
                tls = true;
                "keepalive" = true;
                "nicehash" = false;
              }
            ];
          };
        };
      };
    };

    zephyr = {
      ...
    }: {
      imports = [
        ./configuration.nix
        ./hosts/zephyr/configuration.nix
      ];

      deployment = {
        targetHost = "10.1.1.110";
        targetUser = "root";
      };
    };

    forge = {
      ...
    }: {
      imports = [
        ./configuration.nix
        ./hosts/forge/configuration.nix
      ];

      deployment = {
        targetHost = "10.1.1.130";
        targetUser = "root";
      };
    };

    sentry = {
      ...
    }: {
      imports = [
        ./configuration.nix
        ./hosts/sentry/configuration.nix
      ];

      deployment = {
        targetHost = "10.1.1.140";
        targetUser = "root";
      };
    };
  };
}
