{
  config,
  lib,
  pkgs,
  ...
}: let
  # #309: derive from the declared user instead of hardcoding /home/j_kro.
  userHome = config.users.users.j_kro.home or "/home/j_kro";
in {
  systemd.services.fix-home-permissions = {
    description = "Fix Home Directory Permissions for Nix Builds";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      # Single-string ExecStart: systemd parses the string into argv
      # reliably. (The list form [chmod "755" userHome] serialized
      # as three separate ExecStart= lines on this systemd, running
      # `chmod` with no args -> "missing operand".)
      ExecStart = "${lib.getExe' pkgs.coreutils "chmod"} 755 ${userHome}";
      User = "root";
    };
  };
}
