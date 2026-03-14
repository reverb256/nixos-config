{ pkgs ? import <nixpkgs> {} }:
pkgs.runCommand "steam-run-patched" {
  nativeBuildInputs = [pkgs.bash pkgs.coreutils];
  preferLocalBuild = true;
} ''
  mkdir -p $out/bin
  # Patch steam-run to ignore /data (NFS autofs mount)
  # Note: /etc/nixos is now mounted to /run/nixos-shared (excluded by default)
  sed 's|ignored=(/nix /dev /proc /etc /tmp)|ignored=(/nix /dev /proc /etc /tmp /data)|' \
    ${pkgs.steam-run}/bin/steam-run > $out/bin/steam-run
  chmod +x $out/bin/steam-run
''
