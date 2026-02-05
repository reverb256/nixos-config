# OpenClaw Declarative Container Module
#
# Best practices from:
# - nix-openclaw: Home Manager user service
# - openclaw-ansible: Firewall-first security
#
# Features:
# - Podman container with proper isolation
# - Systemd service
# - Firewall rules (localhost only by default)
# - Full shell tools access inside container
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib; let
  cfg = config.services.openclaw.declarative;
  openclawScript = pkgs.writeShellScript "openclaw-start" ''
    #!/usr/bin/env bash
    set -euo pipefail

    STATE_DIR="${cfg.stateDir}"
    DATA_DIR="${cfg.dataDir}"
    CONFIG_DIR="${cfg.configDir}"
    LOGS_DIR="${cfg.logsDir}"
    WORKSPACE_DIR="${cfg.workspaceDir}"
    WORKFLOWS_DIR="${cfg.workflowsDir}"
    APPROVALS_DIR="${cfg.approvalsDir}"

    mkdir -p "$STATE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$LOGS_DIR" "$WORKSPACE_DIR" "$WORKFLOWS_DIR" "$APPROVALS_DIR"
    chown -R 982:979 "$STATE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$LOGS_DIR" "$WORKSPACE_DIR" "$WORKFLOWS_DIR" "$APPROVALS_DIR" 2>/dev/null || true
    mkdir -p /tmp/openclaw && chown -R 982:979 /tmp/openclaw 2>/dev/null || true
    chmod 777 /tmp/openclaw 2>/dev/null || true
    mkdir -p /tmp/openclaw-982 && chown 982:979 /tmp/openclaw-982 2>/dev/null || true
    chmod 777 /tmp/openclaw-982 2>/dev/null || true
    ${pkgs.podman}/bin/podman rm openclaw-declarative 2>/dev/null || true

    exec ${pkgs.podman}/bin/podman run \
      --name openclaw-declarative \
      --network host \
      --restart unless-stopped \
      -e "OPENCLAW_BIND=${cfg.gatewayBind}" \
      -v "$STATE_DIR:/var/lib/openclaw" \
      -v "$DATA_DIR:/var/lib/openclaw/data" \
      -v "$CONFIG_DIR:/etc/openclaw" \
      -v "$LOGS_DIR:/var/log/openclaw" \
      -v "$WORKSPACE_DIR:/var/lib/openclaw/workspace" \
      -v "$WORKFLOWS_DIR:/var/lib/openclaw/workflows" \
      -v "$APPROVALS_DIR:/var/lib/openclaw/approvals" \
      -v /tmp/openclaw:/tmp/openclaw \
      -v /tmp/openclaw-982:/tmp/openclaw-982 \
      -v ${pkgs.coreutils}/bin:/nix-coreutils:ro \
      -v ${pkgs.findutils}/bin:/nix-findutils:ro \
      -v ${pkgs.git}/bin:/nix-git:ro \
      -v ${pkgs.git}/share:/nix-git-share:ro \
      -v ${pkgs.curl}/bin:/nix-curl:ro \
      -v ${pkgs.wget}/bin:/nix-wget:ro \
      -v ${pkgs.jq}/bin:/nix-jq:ro \
      -v ${pkgs.ripgrep}/bin:/nix-ripgrep:ro \
      -v ${pkgs.fd}/bin:/nix-fd:ro \
      -v ${pkgs.gawk}/bin:/nix-gawk:ro \
      -v ${pkgs.vim}/bin:/nix-vim:ro \
      -v ${pkgs.nano}/bin:/nix-nano:ro \
      -v ${pkgs.gzip}/bin:/nix-gzip:ro \
      -v ${pkgs.unzip}/bin:/nix-unzip:ro \
      -v ${pkgs.yq}/bin:/nix-yq:ro \
      -v ${pkgs.miller}/bin:/nix-miller:ro \
      -v ${pkgs.nodejs_22}/bin:/nix-nodejs:ro \
      -v ${pkgs.pnpm}/bin:/nix-pnpm:ro \
      -v ${pkgs.bun}/bin:/nix-bun:ro \
      -e "OPENCLAW_MODE=${cfg.gatewayMode}" \
      -e "OPENCLAW_BIND=${cfg.gatewayBind}" \
      -e "OPENCLAW_PORT=${toString cfg.port}" \
      -e "OPENCLAW_API_PORT=${toString cfg.apiPort}" \
      -e "OPENCLAW_STATE_DIR=/var/lib/openclaw" \
      -e "OPENCLAW_DATA_DIR=/var/lib/openclaw/data" \
      -e "OPENCLAW_CONFIG_DIR=/etc/openclaw" \
      -e "OPENCLAW_WORKSPACE_DIR=/var/lib/openclaw/workspace" \
      -e "OPENCLAW_WORKFLOWS_DIR=/var/lib/openclaw/workflows" \
      -e "OPENCLAW_APPROVALS_DIR=/var/lib/openclaw/approvals" \
      -e "PATH=/nix-nodejs:/nix-pnpm:/nix-bun:/nix-coreutils:/nix-findutils:/nix-git:/nix-curl:/nix-wget:/nix-jq:/nix-ripgrep:/nix-fd:/nix-gawk:/nix-vim:/nix-nano:/nix-gzip:/nix-unzip:/nix-yq:/nix-miller:/usr/local/bin:/usr/bin:/bin" \
      -e "OPENCLAW_GATEWAY_TOKEN=$(cat /run/agenix/openclaw-gateway-token 2>/dev/null || echo 'MISSING_SECRET')" \
      -e "OPENCLAW_NIX_MODE=1" \
      ${if cfg.enableLegacyEnv then "-e MOLTBOT_NIX_MODE=1" else ""} \
      --memory=${cfg.memory} \
      --cpu-shares=${toString cfg.cpuShares} \
      --user 982:979 \
      --cap-add NET_ADMIN \
      --security-opt "no-new-privileges=true" \
      --label "managed-by=nixos" \
      --label "component=openclaw-gateway" \
      "${cfg.image}" \
      node openclaw.mjs gateway --port ${toString cfg.port} --allow-unconfigured
  '';
in {
  options.services.openclaw.declarative = {
    enable = mkEnableOption "OpenClaw AI Agent Gateway (Declarative Container)";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/openclaw/openclaw:latest";
      description = "OpenClaw container image";
    };

    port = mkOption {
      type = types.int;
      default = 18789;
      description = "OpenClaw gateway port";
    };

    apiPort = mkOption {
      type = types.int;
      default = 18790;
      description = "OpenClaw API port";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw";
      description = "OpenClaw state directory";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw/data";
      description = "OpenClaw data directory";
    };

    configDir = mkOption {
      type = types.str;
      default = "/etc/openclaw";
      description = "OpenClaw config directory";
    };

    logsDir = mkOption {
      type = types.str;
      default = "/var/log/openclaw";
      description = "OpenClaw logs directory";
    };

    workspaceDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw/workspace";
      description = "OpenClaw workspace directory";
    };

    workflowsDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw/workflows";
      description = "Lobster workflow files directory";
    };

    approvalsDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw/approvals";
      description = "Lobster approval files directory";
    };

    memory = mkOption {
      type = types.str;
      default = "4G";
      description = "Container memory limit";
    };

    cpuShares = mkOption {
      type = types.int;
      default = 1024;
      description = "Container CPU shares";
    };

    gatewayMode = mkOption {
      type = types.str;
      default = "local";
      description = "OpenClaw gateway mode";
    };

    gatewayBind = mkOption {
      type = types.str;
      default = "100.81.182.5";
      description = "IP to bind gateway to (Tailscale IP)";
    };

    environmentFile = mkOption {
      type = types.str;
      default = "/run/agenix/openclaw-env";
      description = "Path to environment file";
    };

    enableLegacyEnv = mkOption {
      type = types.bool;
      default = false;
      description = "Enable legacy environment variables";
    };

    firewall = mkOption {
      type = types.attrs;
      default = {
        enabled = true;
      };
      description = "Firewall configuration for OpenClaw";
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # USER & GROUP
    # ============================================================================
    users.users.lobster = {
      isSystemUser = true;
      uid = 982;
      group = "lobster";
      home = "/var/lib/lobster";
    };

    users.groups.lobster = {
      gid = 979;
    };

    # ============================================================================
    # PODMAN & SHELL TOOLS
    # ============================================================================
    environment.systemPackages = [
      pkgs.podman
      pkgs.nodejs_22
      pkgs.pnpm
      pkgs.bun
      pkgs.coreutils
      pkgs.findutils
      pkgs.git
      pkgs.curl
      pkgs.wget
      pkgs.jq
      pkgs.ripgrep
      pkgs.fd
      pkgs.gawk
      pkgs.vim
      pkgs.nano
      pkgs.gzip
      pkgs.unzip
      pkgs.yq
      pkgs.miller
    ];

    # ============================================================================
    # SYSTEMD SERVICE
    # ============================================================================
    systemd.services.openclaw-declarative = {
      description = "OpenClaw AI Agent Gateway";
      after = ["network.target" "tailscaled.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${openclawScript}";
        ExecStop = "${pkgs.podman}/bin/podman stop openclaw-declarative";
        Restart = "on-failure";
        RestartSec = 5;
        User = "root";
        Group = "root";
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };

    # ============================================================================
    # FIREWALL RULES - Tailscale only
    # ============================================================================
    networking.firewall = mkIf cfg.firewall.enabled {
      allowedTCPPorts = [];
      allowedUDPPorts = [];
      interfaces.tailscale0.allowedTCPPorts = [cfg.port cfg.apiPort];
    };

    # ============================================================================
    # XDG DESKTOP PORTAL
    # ============================================================================
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        kdePackages.xdg-desktop-portal-kde
        xdg-desktop-portal-gtk
      ];
    };
  };
}
