{
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf;
in {
  config = mkIf (config.services.cns-watcher.enable || config.services.cns-receiver.enable) {
    # CNS SSH key secret (decrypted at boot)
    age.secrets.cns-ssh-key = {
      file = "/etc/nixos/secrets/cns-ssh-key.age";
      mode = "400";
      owner = "root";
      group = "root";
    };
  };
}
