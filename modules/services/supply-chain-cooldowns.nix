# Supply Chain Security Cooldowns
# Centralizes package manager age-gating configs across the system
# Enforces a 7-day cooling period on all newly published packages
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.supply-chain-cooldowns;
  inherit (lib) mkEnableOption mkIf;
in {
  options.services.supply-chain-cooldowns = {
    enable = mkEnableOption "Supply chain security cooldowns (7-day age gate on all package managers)";
  };

  config = mkIf cfg.enable {
    # Bun: 7-day cooldown on new npm packages
    environment.etc."bunfig.toml".text = ''
      [install]
      minimumReleaseAge = "7d"
    '';

    # Apply user-level configs on boot (user home is not managed by NixOS)
    systemd.services.supply-chain-cooldown-setup = {
      description = "Apply supply chain cooldown configs to user home";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "supply-chain-cooldown-setup" ''
          set -euo pipefail
          HOME="/home/j_kro"

          # Bun config (overwrite — managed declaratively)
          printf '[install]\nminimumReleaseAge = "7d"\n' > "$HOME/.bunfig.toml"
          chown j_kro:users "$HOME/.bunfig.toml"

          # uv config (overwrite — managed declaratively)
          mkdir -p "$HOME/.config/uv"
          printf 'exclude-newer = "7 days"\n' > "$HOME/.config/uv/uv.toml"
          chown -R j_kro:users "$HOME/.config/uv"

          # npm config (append if not present — user may have custom settings)
          if ! grep -q "min-release-age" "$HOME/.npmrc" 2>/dev/null; then
            echo "min-release-age=7" >> "$HOME/.npmrc"
            chown j_kro:users "$HOME/.npmrc"
          fi

          echo "Supply chain cooldown configs applied"
        '';
        User = "root";
      };
    };
  };
}
