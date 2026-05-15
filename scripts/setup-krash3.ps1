# ================================================================
# krash3 Cluster Setup Script (PowerShell)
# Configures Git, SSH, SSO, and clones the nixos-config repo
# Run as: .\setup-krash3.ps1  (from C:\Users\j_kro)
# ================================================================

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " krash3 Cluster Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. Git Config ---
Write-Host "[1/6] Configuring Git..." -ForegroundColor Yellow
git config --global user.name "j_kro"
git config --global user.email "j_kro@lan"
git config --global core.autocrlf true
git config --global init.defaultBranch main
Write-Host "  Done." -ForegroundColor Green

# --- 2. SSH Config ---
Write-Host "[2/6] Configuring SSH..." -ForegroundColor Yellow
$sshDir = "$env:USERPROFILE\.ssh"
if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }

$sshConfig = "$sshDir\config"
if (-not (Test-Path $sshConfig)) {
    @"
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
"@ | Out-File -FilePath $sshConfig -Encoding utf8
    Write-Host "  SSH config created." -ForegroundColor Green
} else {
    Write-Host "  SSH config already exists, skipping." -ForegroundColor Gray
}

# --- 3. Generate SSH keypair (if none exists) ---
Write-Host "[3/6] Checking SSH keys..." -ForegroundColor Yellow
$keyPath = "$sshDir\id_ed25519"
if (-not (Test-Path $keyPath)) {
    Write-Host "  Generating new ed25519 key..." -ForegroundColor Yellow
    ssh-keygen -t ed25519 -C "j_kro@krash3" -f $keyPath -N "" -q
    Write-Host "  Key generated. Public key:" -ForegroundColor Green
    Get-Content "$keyPath.pub"
    Write-Host ""
    Write-Host "  Add it at: https://gitea.lan/user/settings/keys" -ForegroundColor Cyan
} else {
    Write-Host "  SSH key already exists." -ForegroundColor Green
}

# --- 4. Add Gitea SSH host key ---
Write-Host "[4/6] Adding Gitea SSH host key..." -ForegroundColor Yellow
$knownHosts = "$sshDir\known_hosts"
$hostKeys = ssh-keyscan -H gitea.lan 2>$null
if ($hostKeys) {
    Add-Content -Path $knownHosts -Value $hostKeys
    Write-Host "  Gitea host key added." -ForegroundColor Green
} else {
    Write-Host "  Could not fetch Gitea host key (may need manual accept)." -ForegroundColor Yellow
}

# --- 5. Test cluster connectivity ---
Write-Host "[5/6] Testing cluster connectivity..." -ForegroundColor Yellow
Write-Host ""

$services = @(
    @{ Name = "auth.lan (Casdoor SSO)"; Url = "https://auth.lan/" },
    @{ Name = "gitea.lan"; Url = "https://gitea.lan/" },
    @{ Name = "grafana.lan"; Url = "https://grafana.lan/" },
    @{ Name = "haven.lan"; Url = "https://haven.lan/" },
    @{ Name = "ai-inference.lan"; Url = "https://ai-inference.lan/" }
)

foreach ($svc in $services) {
    try {
        $response = Invoke-WebRequest -Uri $svc.Url -SkipCertificateCheck -TimeoutSec 5 -UseBasicParsing
        Write-Host "  $($svc.Name): HTTP $($response.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "  $($svc.Name): FAILED ($($_.Exception.Message))" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "  Testing SSH to zephyr..." -ForegroundColor Yellow
$sshTest = ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=no zephyr "echo OK" 2>$null
if ($sshTest -eq "OK") {
    Write-Host "  zephyr: OK" -ForegroundColor Green
} else {
    Write-Host "  zephyr: FAILED (check SSH key on zephyr)" -ForegroundColor Red
}

# --- 6. Clone nixos-config repo (if not already cloned) ---
Write-Host "[6/6] Checking nixos-config repo..." -ForegroundColor Yellow
$repoPath = "$env:USERPROFILE\nixos-config"
if (-not (Test-Path "$repoPath\.git")) {
    Write-Host "  Cloning nixos-config from Gitea..." -ForegroundColor Yellow
    git clone ssh://git@gitea.lan:2222/j_kro/nixos-config.git $repoPath 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Repo cloned to $repoPath" -ForegroundColor Green
    } else {
        Write-Host "  Clone failed. Add your SSH key to Gitea first:" -ForegroundColor Red
        Write-Host "    https://gitea.lan/user/settings/keys" -ForegroundColor Cyan
    }
} else {
    Write-Host "  Repo already exists at $repoPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Setup complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Add SSH key to Gitea: https://gitea.lan/user/settings/keys" -ForegroundColor White
Write-Host "  2. Login to Casdoor SSO: https://auth.lan" -ForegroundColor White
Write-Host "  3. Clone repo: git clone ssh://git@gitea.lan:2222/j_kro/nixos-config.git" -ForegroundColor White
Write-Host ""
