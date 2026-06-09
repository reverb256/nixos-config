# setup-wsl-ports.ps1
# Run this script as Administrator on krash3 to set up port forwarding for WSL SSH.
# Add to Task Scheduler to run at startup if needed.

Write-Host "=== Krash3 WSL Port Forwarding Setup ===" -ForegroundColor Cyan

# Ensure IP Helper service is running
$svc = Get-Service -Name iphlpsvc -ErrorAction SilentlyContinue
if ($svc.Status -ne "Running") {
    Write-Host "Starting IP Helper service..." -ForegroundColor Yellow
    Set-Service -Name iphlpsvc -StartupType Manual
    Start-Service -Name iphlpsvc
}

# Clean up stale portproxy rules
Write-Host "Cleaning up old rules..." -ForegroundColor Yellow
netsh interface portproxy delete v4tov4 listenport=22222 2>$null
netsh interface portproxy delete v4tov4 listenport=22223 2>$null
netsh interface portproxy delete v4tov4 listenport=2222 2>$null

# Set up portproxy rules for WSL SSH access
# j_kro's WSL: port 22222 -> localhost:22222 (krash3, user j_kro)
Write-Host "Adding portproxy: 22222 -> 127.0.0.1:22222 (j_kro WSL)" -ForegroundColor Green
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=22222 connectaddress=127.0.0.1 connectport=22222

# krash's WSL: port 22223 -> localhost:2223 (krash3-krash, user nixos)
Write-Host "Adding portproxy: 22223 -> 127.0.0.1:2223 (krash WSL)" -ForegroundColor Green
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=22223 connectaddress=127.0.0.1 connectport=2223

# Ensure firewall rules exist
Write-Host "Adding firewall rules..." -ForegroundColor Yellow
netsh advfirewall firewall add rule name="WSL SSH 22222" dir=in action=allow protocol=TCP localport=22222 profile=any 2>$null
netsh advfirewall firewall add rule name="WSL SSH 22223" dir=in action=allow protocol=TCP localport=22223 profile=any 2>$null

# Show result
Write-Host "=== Current Portproxy Rules ===" -ForegroundColor Cyan
netsh interface portproxy show all

Write-Host "=== Done ===" -ForegroundColor Green
Write-Host "Connect from cluster:" -ForegroundColor White
Write-Host "  ssh -p 22222 j_kro@10.1.1.150          (j_kro's WSL)"
Write-Host "  ssh -p 22223 nixos@10.1.1.150          (krash's WSL)"
Write-Host "Or use SSH config entries: krash3-wsl / krash3-krash"
