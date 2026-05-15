#!/usr/bin/env bash
# ================================================================
# setup-krash3-remote.sh — Run from zephyr to configure krash3
# Usage: bash scripts/setup-krash3-remote.sh
# ================================================================
set -euo pipefail

KRASH3="j_kro@10.1.1.150"

echo ""
echo "========================================"
echo " krash3 Remote Setup"
echo "========================================"
echo ""

# 1. Git config
echo "[1/5] Configuring Git on krash3..."
ssh "$KRASH3" "git config --global user.name j_kro && git config --global user.email j_kro@lan && git config --global core.autocrlf true && git config --global init.defaultBranch main && echo '  Done.'"
echo ""

# 2. SSH config
echo "[2/5] Configuring SSH on krash3..."
ssh "$KRASH3" '
mkdir -p ~/.ssh
if [ ! -f ~/.ssh/config ]; then
cat > ~/.ssh/config << '\''EOF'\''
# Cluster SSH config
Host zephyr
    HostName 10.1.1.110
    User j_kro

Host nexus
    HostName 10.1.1.120
    User j_kro

Host forge
    HostName 10.1.1.130
    User j_kro

Host sentry
    HostName 10.1.1.140
    User j_kro

Host krash3
    HostName 10.1.1.150
    User j_kro
EOF
echo "  SSH config created."
else
echo "  SSH config already exists."
fi'
echo ""

# 3. Generate SSH key
echo "[3/5] Checking SSH keys on krash3..."
ssh "$KRASH3" '
if [ ! -f ~/.ssh/id_ed25519 ]; then
  ssh-keygen -t ed25519 -C "j_kro@krash3" -f ~/.ssh/id_ed25519 -N "" -q
  echo "  Key generated. Public key:"
  cat ~/.ssh/id_ed25519.pub
  echo ""
  echo "  Add it at: https://gitea.lan/user/settings/keys"
else
  echo "  SSH key already exists."
  echo "  Public key:"
  cat ~/.ssh/id_ed25519.pub
fi'
echo ""

# 4. Add Gitea host key
echo "[4/5] Adding Gitea SSH host key..."
ssh "$KRASH3" 'ssh-keyscan -H gitea.lan >> ~/.ssh/known_hosts 2>/dev/null; echo "  Done."'
echo ""

# 5. Test connectivity
echo "[5/5] Testing cluster connectivity..."
echo ""
ssh "$KRASH3" '
echo "  Testing auth.lan (Casdoor SSO)..."
curl -sk -o /dev/null -w "    auth.lan: HTTP %{http_code}\n" https://auth.lan/
echo ""
echo "  Testing gitea.lan..."
curl -sk -o /dev/null -w "    gitea.lan: HTTP %{http_code}\n" https://gitea.lan/
echo ""
echo "  Testing grafana.lan..."
curl -sk -o /dev/null -w "    grafana.lan: HTTP %{http_code}\n" https://grafana.lan/
echo ""
echo "  Testing SSH to zephyr..."
ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=no zephyr "echo \"    zephyr: OK\"" 2>/dev/null || echo "    zephyr: FAILED"'
echo ""

echo "========================================"
echo " Setup complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Add SSH key to Gitea: https://gitea.lan/user/settings/keys"
echo "  2. Login to Casdoor SSO: https://auth.lan"
echo "  3. Clone repo: git clone ssh://git@gitea.lan:2222/j_kro/nixos-config.git"
echo ""
