{
  lib,
  pkgs,
  ...
}: {
  systemd.services.fix-home-permissions = {
    description = "Fix Home Directory Permissions for Nix Builds";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      # Single-string ExecStart: systemd parses the string into argv
      # reliably. (The list form [chmod "755" "/home/j_kro"] serialized
      # as three separate ExecStart= lines on this systemd, running
      # `chmod` with no args -> "missing operand".)
      ExecStart = "${lib.getExe' pkgs.coreutils "chmod"} 755 /home/j_kro";
      User = "root";
    };
  };
}
