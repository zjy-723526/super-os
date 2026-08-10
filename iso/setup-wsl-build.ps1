# Super-OS Build Environment Setup (WSL2 + ArchLinux)
# Run as Administrator: right-click PowerShell -> "Run as Administrator"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Super-OS ISO Build Environment Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ─── Step 1: Enable WSL2 ───
Write-Host "[1/3] Enable WSL2..." -ForegroundColor Green

$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
$vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue

$needReboot = $false

if ($wslFeature.State -ne "Enabled") {
    Write-Host "  Installing WSL..." -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
    $needReboot = $true
}
else {
    Write-Host "  WSL already enabled" -ForegroundColor Green
}

if ($vmFeature.State -ne "Enabled") {
    Write-Host "  Installing VirtualMachinePlatform..." -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
    $needReboot = $true
}
else {
    Write-Host "  VirtualMachinePlatform already enabled" -ForegroundColor Green
}

if ($needReboot) {
    Write-Host ""
    Write-Host "  REBOOT REQUIRED!" -ForegroundColor Red
    Write-Host "  Run this script again after reboot" -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "  Reboot now? (y/n)"
    if ($confirm -eq "y") { Restart-Computer }
    exit 0
}

# ─── Step 2: Update WSL2 Kernel ───
Write-Host "[2/3] Update WSL2..." -ForegroundColor Green
wsl --update
wsl --set-default-version 2

# ─── Step 3: Install ArchWSL ───
Write-Host "[3/3] Install Arch Linux (WSL2)..." -ForegroundColor Green

$archList = wsl --list --quiet 2>$null
$archInstalled = $false
if ($archList -match "ArchLinux") {
    $archInstalled = $true
}

if (-not $archInstalled) {
    Write-Host "  Downloading Arch bootstrap..." -ForegroundColor Yellow

    $archUrl = "https://mirrors.tuna.tsinghua.edu.cn/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.zst"
    $archFile = "$env:TEMP\archlinux-bootstrap.tar.zst"

    Invoke-WebRequest -Uri $archUrl -OutFile $archFile -ErrorAction Stop

    Write-Host "  Importing to WSL..."
    wsl --import ArchLinux "$env:LOCALAPPDATA\ArchWSL" $archFile

    Remove-Item $archFile -Force
    Write-Host "  Arch Linux installed!" -ForegroundColor Green
}
else {
    Write-Host "  Arch Linux already installed" -ForegroundColor Green
}

# ─── Step 4: Create setup script for WSL ───
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Configure Arch build environment..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$setupLines = @(
    '#!/bin/bash',
    'set -e',
    'echo "[+] Configuring mirrors..."',
    'echo "Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist',
    'echo "Server = https://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch" >> /etc/pacman.d/mirrorlist',
    '',
    'echo "[+] Init pacman..."',
    'pacman-key --init 2>/dev/null',
    'pacman-key --populate archlinux 2>/dev/null',
    'pacman -Sy --noconfirm archlinux-keyring 2>/dev/null',
    '',
    'echo "[+] Installing build tools..."',
    'pacman -S --noconfirm --needed archiso git base-devel',
    '',
    'echo ""',
    'echo "========================================="',
    'echo " Build environment ready!"',
    'echo "========================================="',
    'echo ""',
    'echo "Now run:"',
    'echo "  cd /mnt/c/Users/zjy/super-os/iso"',
    'echo "  sudo bash build-iso.sh"',
    'echo ""'
)

$setupScript = $setupLines -join "`n"
$setupFile = "$env:TEMP\wsl-setup.sh"
$setupScript | Out-File -FilePath $setupFile -Encoding ASCII

# Run setup inside WSL
Write-Host "Running setup inside WSL..." -ForegroundColor Yellow
wsl -d ArchLinux -- bash "$(wsl -d ArchLinux -- wslpath -u "$setupFile" | Out-String).Trim()"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Environment ready!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "To build the ISO:" -ForegroundColor Cyan
Write-Host "  wsl -d ArchLinux" -ForegroundColor White
Write-Host "  cd /mnt/c/Users/zjy/super-os/iso" -ForegroundColor White
Write-Host "  sudo bash build-iso.sh" -ForegroundColor White
Write-Host ""
