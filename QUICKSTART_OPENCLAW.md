# OpenClaw Quadlet Configuration - Simple Usage Example
# Add this to your hosts/zephyr/configuration.nix to enable OpenClaw
#
# This example enables OpenClaw with:
# - Token-based authentication
# - Workspace symlink to /home/j_kro/workspace
# - Security hardening (seccomp, AppArmor, firewall)
# - localhost-only binding
# - Resource limits
#
# ============================================================================
# STEP 1: Generate Secure Token
# ============================================================================
# Generate a 256-bit random token:
# ```bash
# openssl rand -hex 32
# ```
#
# Store the token securely:
# Option A - Environment variable (simple, but visible in processes)
#   OPENCLAW_TOKEN=your-token-here
#
# Option B - Agenix (recommended, encrypted at rest)
#   1. Create age key (if needed):
#     age-keygen -o openclaw-key.age
#   2. Add to flake.nix inputs:
#     age.secrets = {
#       file = ./secrets/openclaw-token.age;
#       mode = "600";  # root read-only, group read
#       owner = "root";
#       group = "nixos";  # For nixos-rebuild switch
#     }
#   3. Rebuild:
#     sudo nixos-rebuild switch
#
# ============================================================================
# STEP 2: Add Configuration to hosts/zephyr/configuration.nix
# ============================================================================
# Add this line to imports:
# ```
# ./modules/quadlet-openclaw.nix
# ```
#
# Then enable the module with minimal config:
# ```
# services.openclaw-quadlet = {
#   enable = true;
#   workspacePath = "/home/j_kro/workspace";
# };
# ```
#
# ============================================================================
# STEP 3: Rebuild and Verify
# ============================================================================
# ```bash
# Rebuild NixOS
# sudo nixos-rebuild switch
#
# Verify OpenClaw is running
# podman ps
# systemctl status quadlet-openclaw
#
# Access OpenClaw web terminal
# http://localhost:18090/
# Or via Tailscale: https://openclaw-yoursite.tailnetname.ts.net:18090/
# ```
#
# ============================================================================
# SECURITY FEATURES ENABLED BY DEFAULT
# ============================================================================
# This configuration applies all recommended security settings:
#
# ### Authentication
# - Token-based authentication
# - Token stored via environment variable
#
# ### Runtime Security
# - OpenClaw seccomp profile (hardened system call filtering)
# - AppArmor profile (Mandatory access control)
# - No new privileges
# - Device policy: closed
#
# ### Filesystem Security
# - Read-only: /etc, /usr, /bin, /lib (system directories)
# - Read-write: /workspace (only the container's working directory)
# - Symlink following: disabled (prevents path traversal)
#
# ### Network Security
# - Bind to 127.0.0.1:18090 (localhost only)
# - Firewall: Blocks direct Podman access, only allows port 18090
# - No external port exposure
#
# ### Resource Limits
# - PIDs: 500 (prevent fork bombs)
# - Memory: 2G reservation, 4G hard limit
# - CPU: 200% quota (2 cores on 32-core system)
#
# ### Audit & Monitoring
# - Journald logging
# - Rate limiting (30s interval, 1000 burst)
# - Podman auto-update enabled
#
# ============================================================================
# ADVANCED OPTIONS (EDIT IN hosts/zephyr/configuration.nix)
# ============================================================================
# Enable Tailscale for secure remote access:
# ```nix
# services.openclaw-quadlet.networking.enableTailscale = true;
# ```
#
# Adjust resource limits for heavy workloads:
# ```nix
# services.openclaw-quadlet.resources = {
#   pidsLimit = 1000;
#   memoryLimit = "8G";
#   cpuQuota = 400;
# };
# ```
#
# Switch security mode (options: strict, balanced, development):
# ```nix
# services.openclaw-quadlet.securityMode = "strict";
# ```
#
# ============================================================================
# COMPLETE SECURITY CHECKLIST
# ============================================================================
# After deployment, verify:
#
# [ ] Token generated (256-bit random)
# [ ] Token stored securely
# [ ] Seccomp profile enabled
# [ ] AppArmor profile loaded
# [ ] Firewall blocking external access
# [ ] Resource limits applied
# [ ] Workspace symlink created
# [ ] OpenClaw image auto-updating
#
# ============================================================================
# TROUBLESHOOTING
# ============================================================================
# Container won't start?
# ```bash
# podman ps | grep openclaw
# ```
#
# Check container status:
# ```bash
# systemctl status quadlet-openclaw
# journalctl -u quadlet-openclaw -n 100
# ```
#
# Verify workspace mount:
# ```bash
# podman inspect openclaw | jq '.[0].Mounts'
# ```
#
# Expected output:
# [{
#   "destination": "/workspace",
#   "source": "/home/j_kro/workspace",
#   "type": "bind"
# }]
# ```
#
# ============================================================================
# SECURITY BEST PRACTICES
# ============================================================================
# 1. Never use default tokens (always generate 256-bit random)
# 2. Regularly rotate tokens (every 30 days recommended)
# 3. Never commit tokens to version control
# 4. Never bind to 0.0.0.0 (always use 127.0.0.1)
# 5. Never expose ports publicly without Tailscale
# 6. Monitor logs for suspicious activity
# 7. Keep OpenClaw image updated (auto-update enabled)
# 8. Use strong unique tokens (256-bit minimum)
# 9. Review audit logs regularly: journalctl -u quadlet-openclaw -f
# 10. Enable AppArmor (it's already enabled in your config)
#
# ============================================================================
# ADDITIONAL MODULES FOR ENHANCED SETUP
# ============================================================================
# The quadlet-openclaw module supports additional features:
#
# Tailscale integration (for secure remote access):
# ```nix
# services.tailscale.enable = true;
# services.tailscale.interfaceName = "tailscale0";
# ```
#
# Monitoring integration (Prometheus):
# ```nix
# services.prometheus.scrapeConfigs = [{
#   job_name = "openclaw";
#   scrape_interval = "15s";
#   static_configs = [{
#     targets = ["localhost:18090"];
#   }];
# }];
# ```
#
# ============================================================================
# LINKS & RESOURCES
# ============================================================================
# OpenClaw Documentation: https://github.com/openclaw/openclaw-host-kit
# OpenClaw Security Guide: https://securemolt.com/guides/gateway-hardening/
# Quadlet-Nix Documentation: https://seiarotg.github.io/quadlet-nix/introduction.html
# Podman Quadlets Documentation: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html
# Reverb-OS Cluster Docs: /etc/nixos/AGENTS.md
