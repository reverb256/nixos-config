# scripts/wsl-autostart.ps1
#
# "Start WSL with Windows" — NixOS-WSL has no auto-start option of its own
# (it only manages systemd-inside-WSL via wsl.nativeSystemd). The Windows side
# must launch the distro. This creates a Windows Task Scheduler task that runs
# `wsl.exe -d <Distro>` at user logon (so systemd + sshd come up without you
# opening a terminal).
#
# Usage (run from an elevated PowerShell, or it will prompt):
#   powershell -ExecutionPolicy Bypass -File scripts/wsl-autostart.ps1 -Distro NixOS [-TaskName "NixOS WSL Autostart"]
#
# The distro name must match the WSL registration name:
#   - this PC (krash3):  NixOS   -> wsl-krash3
#   - krash2 (10.1.1.79): NixOS  -> wsl-krash2
# (Both are registered as "NixOS" on their respective Windows hosts; the WSL
#  hostname inside differs: nixos-wsl-krash3 / nixos-wsl-krash2.)

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Distro,
  [string]$TaskName = "$Distro WSL Autostart"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  Write-Error "wsl.exe not found. Install WSL first."
  exit 1
}

# Confirm the distro is registered
$registered = wsl.exe --list --quiet | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq $Distro }
if (-not $registered) {
  Write-Error "Distro '$Distro' is not registered. Import/build it first."
  exit 1
}

# Remove any prior version of the task
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  Write-Host "Removed existing task '$TaskName'."
}

$action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d $Distro"
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "Launch NixOS-WSL distro '$Distro' at user logon so systemd + sshd start automatically." | Out-Null

Write-Host "Created scheduled task '$TaskName' (trigger: AtLogOn -> wsl.exe -d $Distro)."
Write-Host "Test now with: Start-ScheduledTask -TaskName '$TaskName'"
