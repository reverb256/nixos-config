# Home-Manager Integration
#
# This module enables declarative home directory management for j_kro
#
# Architecture:
#   - Declarative: .config/*, dotfiles (managed by home-manager)
#   - Persistent: SSH, GPG, Zen Browser (managed by preservation module)
#   - Data: User data (not managed declaratively)
#
# Import per-host:
#   hosts/zephyr/configuration.nix: imports = [ ../../modules/home-manager/zephyr.nix ];
#   hosts/nexus/configuration.nix:  imports = [ ../../modules/home-manager/nexus.nix ];
#   hosts/forge/configuration.nix:  imports = [ ../../modules/home-manager/forge.nix ];
#   hosts/sentry/configuration.nix: imports = [ ../../modules/home-manager/sentry.nix ];
#
# Scope:
#   - Shell config (bash, fish)
#   - Git configuration
#   - Common dotfiles (.screenrc, .gitconfig)
#   - .config/* (alacritty, fastfetch, etc.)
#
# NOT in scope:
#   - Crypto wallets (Zen Browser) → preservation module
#   - SSH keys (already in preservation)
#   - GPG keys (already in preservation)
#   - User data (~/models, ~/projects, downloads)

{ config, lib, pkgs, inputs, ... }:
let
  inherit (lib) mkDefault mkIf mkMerge;
in
{
  # Home-Manager is already imported via common-modules-list.nix
  # This module configures j_kro's declarative home

  # Import per-host configuration
  imports = [
    ./common.nix
    ./zephyr.nix
    ./nexus.nix
    ./forge.nix
    ./sentry.nix
  ];

  # Make home-manager state persistent across NixOS generations
  users.users.j_kro = {
    # Home dir is already managed by disko or host-specific config
    # Don't manage it here to avoid conflicts
  };

  # Ensure home-manager activation happens at boot
  systemd.services.home-manager-j_kro = {
    enable = true;
    description = "Home Manager for j_kro";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
  };
}