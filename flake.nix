{
  inputs = {
    garnix-lib.url = "github:garnix-io/garnix-lib";
    Rust.url = "github:garnix-io/rust-module";
    NodeJS.url = "github:garnix-io/nodejs-module";
    PostgreSQL.url = "github:garnix-io/postgresql-module";
    UptimeKuma.url = "github:garnix-io/uptime-kuma-module";
    User.url = "github:garnix-io/user-module";
  };

  nixConfig = {
    extra-substituters = [ "https://cache.garnix.io" ];
    extra-trusted-public-keys = [ "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=" ];
  };

  outputs = inputs: inputs.garnix-lib.lib.mkModules {
    modules = [
      inputs.Rust.garnixModules.default
      inputs.NodeJS.garnixModules.default
      inputs.PostgreSQL.garnixModules.default
      inputs.UptimeKuma.garnixModules.default
      inputs.User.garnixModules.default
    ];

    config = { pkgs, ... }: {
      rust = {
        rust-project = {
          buildDependencies = [  ];
          devTools = [  ];
          runtimeDependencies = [  ];
          src = ./.;
          webServer = null;
        };
      };
      nodejs = {
        nodejs-project = {
          buildDependencies = [  ];
          devTools = [  ];
          prettier = false;
          runtimeDependencies = [  ];
          src = ./.;
          testCommand = "npm run test";
          webServer = null;
        };
      };
      postgresql = {
        postgresql-project = {
          port = 5432;
        };
      };
      uptimeKuma = {
        uptimeKuma-project = {
          path = "/";
          port = 3001;
        };
      };
      user = {
        user-project = {
          authorizedSshKeys = [  ];
          groups = [ "wheel" ];
          shell = "fish";
          user = "j_kro";
        };
      };

      garnix.deployBranch = "main";
    };
  };
}
