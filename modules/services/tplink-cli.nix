{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "tplink" ''
      #!/usr/bin/env bash
      exec /etc/nixos/scripts/tplink "$@"
    '')
  ];

  programs.fish.interactiveShellInit = ''
    abbr --add tplink '/etc/nixos/scripts/tplink'
    abbr --add sw '/etc/nixos/scripts/tplink status'
    abbr --add swweb '/etc/nixos/scripts/tplink web'
  '';
}
