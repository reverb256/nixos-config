{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
# secretspec-example — DEPRECATED as of Phase 1 rollout. The real
# validation is `modules/system/secretspec-validator.nix`, which runs
# `secretspec check` as a systemd one-shot on multi-user.target. The
# purpose of THIS module (Phase 4: secretspec resolves secrets and
# ssh-pushes each to /etc/credstore via `systemd-creds encrypt`) is
# preserved here as a documented reference but not wired up.
#
# Migration path: Phase 4 is ready — upstream secretspec 0.18.0 (fork
# deleted 2026-08-07) supports sops:// aliases natively. When systemd credentials
# integration lands, rename this file to `secretspec-systemd-creds.nix`, port the
# creds attr below forward, and add it to modules/default.nix. Until then, treat
# this file as documentation only.
#
# For the running validator today: services.secretspec-validator.enable.
# This file's `enable` defaults remain false so accidental imports can't
# silently spin a sleep-infinity service.
#
# secretspec-example — DISABLED by default. Demonstrates the Phase 4 deploy
# pattern: secretspec resolves secrets, ssh-pushes each to /etc/credstore
# via `systemd-creds encrypt`, and systemd exposes them at
# /run/credentials/<name>/<secret> via LoadCredentialEncrypted=.
#
# Workflow:
#   1. Edit creds attr below to declare the workload's keys.
#   2. Build the package: `nix build .#secretspec-provider-sops`
#      (so secretspec check-style resolution works on NixOS-side runs).
#   3. Run the deploy script from a workstation:
#        scripts/phase4-deploy-example.sh push-creds <host> secretspec-example \
#          <KEY1> <KEY2> ...
#      This writes /etc/credstore/<key>.cred on the target host.
#   4. Set services.secretspec-example.enable = true on the host's
#      configuration.nix (or in this module's host-specific block).
#   5. `sudo nixos-rebuild switch --flake .#<host>` — service starts
#      with creds from /run/credentials/.
#
# Real workloads should fork this module rather than enable it directly;
# the bash-sleep ExecStart is illustrative only.
  let
    cfg = config.services.secretspec-example;
  in {
    options.services.secretspec-example = {
      enable = mkEnableOption "Phase 4 example — secretspec + systemd-creds + LoadCredentialEncrypted= (disabled by default)";

      creds = mkOption {
        type = types.attrsOf types.str;
        default = {
          example-token = "token";
        };
        example = {
          cloudflared-token = "cloudflare_tunnel_token";
          grafana-admin = "grafana_admin_password";
        };
        description = ''
          Map of `<cred-file-stem>` → `<secret-name>` consumed by the
          service's LoadCredentialEncrypted list. Each entry produces
          a `/etc/credstore/<stem>.cred` on the host (pushed by the
          deploy script) and exposes it as `/run/credentials/<svc>/<secret>`.
        '';
      };
    };

    config = mkIf cfg.enable {
      systemd.services.secretspec-example = {
        description = "Example service consuming secretspec-pushed credentials (Phase 4 deploy pattern)";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        serviceConfig = {
          Type = "simple";
          # NOTE: Phase-4 deploy pattern not yet wired. This ExecStart is
          # intentionally a no-op (`/bin/false`) so that an accidental
          # `imports = [ ./services/secretspec-example.nix ]` regression
          # cannot silently spin a sleep-infinity service. The real
          # running validator lives at
          # `modules/system/secretspec-validator.nix`.
          ExecStart = "/bin/false";
          DynamicUser = true;
          LoadCredentialEncrypted =
            mapAttrsToList (
              stem: secretName: "${secretName}:/etc/credstore/${stem}.cred"
            )
            cfg.creds;
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    };
  }
