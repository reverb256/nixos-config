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
      # Use the list form of ExecStart (no shell, no bash -c). The ~j_kro
      # tilde would otherwise need shell expansion; use the literal path.
      ExecStart = [ (lib.getExe' pkgs.coreutils "chmod") "755" "/home/j_kro" ];
      User = "root";
    };
  };
}
