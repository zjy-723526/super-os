@echo off
echo ======================================
echo  Super-OS WSL2 Setup (Admin)
echo ======================================
echo.

echo [1/4] Enable WSL feature...
dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
echo.

echo [2/4] Enable VirtualMachinePlatform...
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
echo.

echo [3/4] Install WSL2 kernel update...
msiexec /i "%TEMP%\wsl_update_x64.msi" /quiet /norestart
echo.

echo [4/4] Set WSL2 as default...
wsl --set-default-version 2
echo.

echo ======================================
echo  DONE! Please REBOOT now.
echo  After reboot, run: quick-build.ps1
echo ======================================
pause
