@echo off
REM ================================================================
REM krash3 Cluster Setup Script
REM Configures Git, SSH, and SSO for the NixOS cluster
REM Run as: scripts\setup-krash3.bat  (from C:\Users\j_kro)
REM ================================================================

echo.
echo ========================================
echo  krash3 Cluster Setup
echo ========================================
echo.

REM --- 1. Git Config ---
echo [1/5] Configuring Git...
git config --global user.name "j_kro"
git config --global user.email "j_kro@lan"
git config --global core.autocrlf true
git config --global init.defaultBranch main
echo  Done.

REM --- 2. SSH Config ---
echo [2/5] Configuring SSH...
if not exist "%USERPROFILE%\.ssh" mkdir "%USERPROFILE%\.ssh"

REM Only write if file doesn't exist
if not exist "%USERPROFILE%\.ssh\config" (
    echo # Cluster SSH config > "%USERPROFILE%\.ssh\config"
    echo. >> "%USERPROFILE%\.ssh\config"
    echo Host zephyr >> "%USERPROFILE%\.ssh\config"
    echo     HostName 10.1.1.110 >> "%USERPROFILE%\.ssh\config"
    echo     User j_kro >> "%USERPROFILE%\.ssh\config"
    echo. >> "%USERPROFILE%\.ssh\config"
    echo Host nexus >> "%USERPROFILE%\.ssh\config"
    echo     HostName 10.1.1.120 >> "%USERPROFILE%\.ssh\config"
    echo     User j_kro >> "%USERPROFILE%\.ssh\config"
    echo. >> "%USERPROFILE%\.ssh\config"
    echo Host forge >> "%USERPROFILE%\.ssh\config"
    echo     HostName 10.1.1.130 >> "%USERPROFILE%\.ssh\config"
    echo     User j_kro >> "%USERPROFILE%\.ssh\config"
    echo. >> "%USERPROFILE%\.ssh\config"
    echo Host sentry >> "%USERPROFILE%\.ssh\config"
    echo     HostName 10.1.1.140 >> "%USERPROFILE%\.ssh\config"
    echo     User j_kro >> "%USERPROFILE%\.ssh\config"
    echo. >> "%USERPROFILE%\.ssh\config"
    echo Host krash3 >> "%USERPROFILE%\.ssh\config"
    echo     HostName 10.1.1.150 >> "%USERPROFILE%\.ssh\config"
    echo     User j_kro >> "%USERPROFILE%\.ssh\config"
    echo  Done.
) else (
    echo  SSH config already exists, skipping.
)

REM --- 3. Generate SSH keypair (if none exists) ---
echo [3/5] Checking SSH keys...
if not exist "%USERPROFILE%\.ssh\id_ed25519" (
    echo  Generating new ed25519 key...
    ssh-keygen -t ed25519 -C "j_kro@krash3" -f "%USERPROFILE%\.ssh\id_ed25519" -N "" -q
    echo  Key generated. Add the public key to Gitea:
    type "%USERPROFILE%\.ssh\id_ed25519.pub"
    echo.
    echo  Paste it at: https://gitea.lan/user/settings/keys
) else (
    echo  SSH key already exists.
)

REM --- 4. Add Gitea SSH host key ---
echo [4/5] Adding Gitea SSH host key...
ssh-keyscan -H gitea.lan >> "%USERPROFILE%\.ssh\known_hosts" 2>nul
ssh-keyscan -H 10.1.1.100 >> "%USERPROFILE%\.ssh\known_hosts" 2>nul
echo  Done.

REM --- 5. Test cluster connectivity ---
echo [5/5] Testing cluster connectivity...
echo.
echo  Testing auth.lan (Casdoor SSO)...
curl -sk -o nul -w "  auth.lan: HTTP %%{http_code}\n" https://auth.lan/
echo.
echo  Testing gitea.lan...
curl -sk -o nul -w "  gitea.lan: HTTP %%{http_code}\n" https://gitea.lan/
echo.
echo  Testing grafana.lan...
curl -sk -o nul -w "  grafana.lan: HTTP %%{http_code}\n" https://grafana.lan/
echo.
echo  Testing SSH to zephyr...
ssh -o ConnectTimeout=3 -o BatchMode=yes zephyr "echo '  zephyr: OK'" 2>nul || echo "  zephyr: FAILED (check SSH key)"
echo.

echo ========================================
echo  Setup complete!
echo ========================================
echo.
echo  Next steps:
echo   1. Add your SSH public key to Gitea:
echo      https://gitea.lan/user/settings/keys
echo   2. Clone the config repo:
echo      git clone ssh://git@gitea.lan:2222/j_kro/nixos-config.git
echo   3. Login to Casdoor SSO:
echo      https://auth.lan
echo.
pause
