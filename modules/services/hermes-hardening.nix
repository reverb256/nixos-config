# Hermes Agent Hardening Module
#
# Adds hardening on top of services.hermes-agent from NousResearch flake:
# - Terminal dangerous patterns (destructive command blocking)
# - Skills permissions fix at boot (postStart script)
# - Documents injection (CRITICAL RULES, workflows)
#
# Usage (in host configuration):
#   services.hermes-hardening.enable = true;
#   services.hermes-hardening.user = "j_kro";
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-hardening;

  # Dangerous patterns based on Junction Panel + arXiv + lived experience
  # Three-part policy: safe (allow), review (ask), destructive (block)
  dangerousPatterns = [
    # System lifecycle
    "shutdown.*now"
    "reboot.*now"
    "systemctl.*reboot"
    "systemctl.*poweroff"
    "systemctl.*halt"

    # VM/Container lifecycle
    "virsh.*(shutdown|destroy|reboot|undefine)"
    "virt-xml.*delete"
    "docker.*rm -f"
    "docker.*rm.*--force"
    "docker.*rmi.*-f"
    "podman.*rm -f"
    "podman.*rmi.*-f"
    "kubectl.*delete.*--all"
    "kubectl.*delete.*pod.*--all"
    "kubectl.*delete.*deploy.*--all"
    "kubectl.*delete.*ns.*--all"
    "systemctl.*restart.*docker"
    "systemctl.*restart.*libvirtd"
    "systemctl.*restart.*podman"

    # Windows disk operations
    "mountvol.* /p"
    "diskpart.*clean"
    "format.*volume"
    "Remove-PartitionAccessPath"
    "Initialize-Disk.*-PartitionStyle GPT"
    "Clear-Disk"

    # RAID/storage destructive
    "mdadm.*--stop"
    "mdadm.*--zero-superblock"
    "wipefs.* -a"
    "wipefs.*--all"
    "dd.*if=/dev/zero"
    "shred"
    "sgdisk.*-Z"
    "parted.*rm"

    # System reboot/shutdown (alternate forms)
    "poweroff"
    "halt"
    "init 0"
    "telinit 0"

    # Data destructive
    "rm -rf .* /"
    "rm -rf /etc/nixos"
    "rm -rf /home"
    "rm -rf /root"
    "rm -rf /var"
    "rm -rf /usr"
    "rm -rf /opt"
    "rm -rf /srv"
    "rm -rf /data"
    "rm -rf /boot"
    "rm -rf /nix"

    # Git destructive
    "git.*push.*--force"
    "git.*push.*-f"
    "git.*reset.*--hard"
    "git.*checkout.*--force"
    "git.*clean.*-fd"
    "git.*clean.*-ffdx"
    "git.*branch.*-D"

    # Database destructive
    "psql.*DROP.*DATABASE"
    "psql.*DROP.*TABLE"
    "psql.*DROP.*SCHEMA"
    "psql.*TRUNCATE"
    "mysql.*DROP.*DATABASE"
    "mysql.*DROP.*TABLE"
    "mysql.*TRUNCATE"

    # Mining/production (context-dependent, ask first)
    "killall.*peakminer"
    "killall.*lpminer"
    "pkill.*peakminer"
    "pkill.*lpminer"
    "systemctl.*stop.*peakminer"
    "systemctl.*stop.*lpminer"
    "systemctl.*stop.*mining"

    # NixOS destructive (manual nixos-rebuild bypass)
    "nixos-rebuild.*switch"
    "nixos-rebuild.*test"
    "nixos-rebuild.*boot"
    "nix-build.*<nixos-config>"
  ];

  # PostStart script to fix skills permissions (0644 for SKILL.md, 0755 for dirs)
  skillsPermsFixScript = pkgs.writeShellScript "hermes-skills-perms-fix" ''
    set -euo pipefail

    HERMES_HOME="/home/${cfg.user}/.hermes"

    # Fix SKILL.md permissions (0644)
    if [ -d "$HERMES_HOME/skills" ]; then
      find "$HERMES_HOME/skills" -name "SKILL.md" -exec chmod 644 {} +
      echo "[hermes-skills-perms] Fixed SKILL.md permissions to 0644"
    fi

    # Fix directory permissions (0755)
    if [ -d "$HERMES_HOME/skills" ]; then
      find "$HERMES_HOME/skills" -type d -exec chmod 755 {} +
      echo "[hermes-skills-perms] Fixed directory permissions to 0755"
    fi

    # Fix profile skills (recursively)
    for profile_dir in "$HERMES_HOME"/profiles/*/skills; do
      if [ -d "$profile_dir" ]; then
        find "$profile_dir" -name "SKILL.md" -exec chmod 644 {} +
        find "$profile_dir" -type d -exec chmod 755 {} +
        echo "[hermes-skills-perms] Fixed permissions for profile: $(basename $(dirname "$profile_dir"))"
      fi
    done
  '';
in {
  options.services.hermes-hardening = {
    enable = lib.mkEnableOption "Hermes Agent hardening (dangerous patterns, skills permissions)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User who runs Hermes Agent";
    };

    dangerousPatterns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = dangerousPatterns;
      description = "Dangerous command patterns to block (terminal.dangerous_patterns)";
    };
  };

  config = lib.mkIf cfg.enable {
    # hermes-cli must be enabled for hardening to apply
    services.hermes-cli.enable = lib.mkDefault true;

    # Run the permissions fix as a one-shot service after hermes-cli
    systemd.services.hermes-skills-perms = {
      description = "Fix Hermes skills permissions";
      after = ["agenix.service" "network.target"];
      wants = ["agenix.service"];
      wantedBy = ["multi-user.target"];
      path = with pkgs; [coreutils findutils];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        RemainAfterExit = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = ["/home/${cfg.user}/.hermes"];
        ExecStart = skillsPermsFixScript;
      };
    };

    # TODO: Integrate terminal.dangerous_patterns into Hermes config
    # This requires writing to ~/.hermes/config.yaml or using the MCP server
    # For now, this is a reference-only module
  };
}