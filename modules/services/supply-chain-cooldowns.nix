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
    environment.etc."bunfig.toml".text = ''
      [install]
      minimumReleaseAge = "7d"
    '';

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

          printf '[install]\nminimumReleaseAge = "7d"\n' > "$HOME/.bunfig.toml"
          chown j_kro:users "$HOME/.bunfig.toml"

          mkdir -p "$HOME/.config/uv"
          printf 'exclude-newer = "7 days"\n' > "$HOME/.config/uv/uv.toml"
          chown -R j_kro:users "$HOME/.config/uv"

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
