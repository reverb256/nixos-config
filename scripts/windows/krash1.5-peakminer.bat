@echo off
REM PeakMiner for krash1.5 (Windows 10, RTX 4060)
REM Download peakminer-1.0.8-windows-x86_64.zip from:
REM https://github.com/peakminer/peakminer/releases/download/v1.0.8/peakminer-1.0.8-windows-x86_64.zip
REM Extract to C:\peakminer\ and run this script on startup.

REM Kill any existing lpminer first
taskkill /f /im lpminer.exe 2>nul
timeout /t 2 /nobreak >nul

REM Start PeakMiner - Pearl mining on Kryptex pool
REM Wallet: krxXVNVMM7.krash1.5-4060
REM Power limit: 100W (matches other 4060s)
REM Temp stop: 72C (resume at 62C)
C:\peakminer\peakminer.exe ^
  --coin pearl ^
  --url stratum+tcp://prl-us.kryptex.network:7048 ^
  --url stratum+tcp://prl.kryptex.network:7048 ^
  --user krxXVNVMM7.krash1.5-4060 ^
  --devices all ^
  --gpu-power 100 ^
  --gpu-temp-stop 72 ^
  --api-port 4068 ^
  --log-append ^
  --log-file C:\peakminer\peakminer.log

pause
