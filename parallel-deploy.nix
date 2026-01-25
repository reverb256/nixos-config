# Parallel SSH deployment using GNU parallel
# Faster than sequential SSH, supports simultaneous execution
{lib, ...}: let
  # List of remote hosts
  remoteHosts = ["nexus" "forge" "sentry"];

  # SSH command template
  sshCmd = host: "ssh j_kro@${host} \"sudo nixos-rebuild switch --flake /etc/nixos#${host}\"";

  # Generate parallel commands
  parallelCmds = lib.concatStringsSep " ::: " (map sshCmd remoteHosts);
in {
  # This creates a derivation that runs parallel deployment
  parallel-deploy = lib.mkDerivation {
    name = "parallel-cluster-deploy";
    buildCommand = ''
      echo "Starting parallel deployment to ${toString (builtins.length remoteHosts)} hosts..."
      parallel --no-notice --ungroup ::: ${parallelCmds}
      echo "Parallel deployment complete!"
    '';
    buildInputs = [
      /*
      GNU parallel would be added here
      */
    ];
  };
}
