# TP-Link Switch Management CLI
# Wrapper for managing TP-Link Easy Smart Switches
{ lib, pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "tplink" ''
      #!/usr/bin/env bash
      exec /etc/nixos/scripts/tplink "$@"
    '')
  ];

  # Zsh shell aliases for quick access
  programs.zsh.initExtra = lib.mkAfter ''
    # TP-Link Switch Management aliases
    alias tplink='/etc/nixos/scripts/tplink'
    alias sw='/etc/nixos/scripts/tplink status'
    alias swweb='/etc/nixos/scripts/tplink web'
  '';
}
