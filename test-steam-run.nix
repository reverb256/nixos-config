{ pkgs ? import <nixpkgs> {} }:
pkgs.runCommand "steam-run-patched" {
  nativeBuildInputs = [pkgs.bash pkgs.coreutils];
  preferLocalBuild = true;
} ''
  mkdir -p $out/bin
  # Patch steam-run to ignore /data and /etc/nixos (NFS mount issues)
  sed 's|ignored=(/nix /dev /proc /etc /tmp)|ignored=(/nix /dev /proc /etc /tmp /data /etc/nixos)|' \
    ${pkgs.steam-run}/bin/steam-run > $out/bin/steam-run
  chmod +x $out/bin/steam-run
''
