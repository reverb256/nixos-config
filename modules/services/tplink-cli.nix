# TP-Link Switch Management CLI
# Wrapper for managing TP-Link Easy Smart Switches
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "tplink" ''
      #!/usr/bin/env bash
      exec /etc/nixos/scripts/tplink "$@"
    '')
  ];

  # Fish shell abbreviation for quick access
  programs.fish.interactiveShellInit = ''
    # TP-Link Switch Management abbreviations
    abbr --add tplink '/etc/nixos/scripts/tplink'
    abbr --add sw '/etc/nixos/scripts/tplink status'
    abbr --add swweb '/etc/nixos/scripts/tplink web'
  '';
}
