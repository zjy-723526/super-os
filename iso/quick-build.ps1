# Super-OS Quick Build - Skip slow WSL kernel download
# 直接下载 Arch bootstrap (清华镜像, 飞快) 并导入 WSL

Write-Host "=== Super-OS Quick Build ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Download Arch bootstrap from fast Chinese mirror
$bootstrapUrl = "https://mirrors.tuna.tsinghua.edu.cn/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.zst"
$bootstrapFile = "$env:TEMP\arch-bootstrap.tar.zst"

Write-Host "[1/4] Download Arch bootstrap (Tsinghua mirror)..." -ForegroundColor Green
Write-Host "  URL: $bootstrapUrl"

# Remove old file if exists
if (Test-Path $bootstrapFile) { Remove-Item $bootstrapFile -Force }

# Download with progress
$ProgressPreference = 'Continue'
Invoke-WebRequest -Uri $bootstrapUrl -OutFile $bootstrapFile -UseBasicParsing

$fileSize = (Get-Item $bootstrapFile).Length / 1MB
Write-Host "  Downloaded: $([math]::Round($fileSize, 1)) MB" -ForegroundColor Green

# Step 2: Remove old Arch WSL if exists
Write-Host "[2/4] Import to WSL..." -ForegroundColor Green
$existing = wsl --list --quiet 2>$null
if ($existing -match "ArchLinux") {
    Write-Host "  Removing old ArchLinux..."
    wsl --unregister ArchLinux 2>$null
}

wsl --import ArchLinux "$env:LOCALAPPDATA\ArchWSL" $bootstrapFile
Remove-Item $bootstrapFile -Force
Write-Host "  ArchLinux imported!" -ForegroundColor Green

# Step 3: Create init script
Write-Host "[3/4] Setup build environment..." -ForegroundColor Green

$initFile = "$env:TEMP\arch-init.sh"
@"
#!/bin/bash
set -e
echo '[+] Configuring China mirrors...'
echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/\$repo/os/\$arch' > /etc/pacman.d/mirrorlist
echo 'Server = https://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch' >> /etc/pacman.d/mirrorlist
echo '[+] Init pacman keys...'
pacman-key --init 2>/dev/null || true
pacman-key --populate archlinux 2>/dev/null || true
pacman -Sy --noconfirm archlinux-keyring 2>/dev/null || true
echo '[+] Installing build tools (archiso, git)...'
pacman -S --noconfirm --needed archiso git base-devel
echo ''
echo '=== Build environment ready! ==='
"@ | Out-File -FilePath $initFile -Encoding ascii

# Fix newlines and run init inside WSL
Write-Host "  Running init (installing packages, ~2-5 min)..." -ForegroundColor Yellow
$wslInitPath = "/mnt/c" + ($initFile -replace ':', '') -replace '\\', '/'
$wslInitPath = $wslInitPath -replace '//', '/'
wsl -d ArchLinux -- bash "$wslInitPath"

# Step 4: Done
Write-Host "[4/4] Ready!" -ForegroundColor Green
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " BUILD THE ISO:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  wsl -d ArchLinux" -ForegroundColor White
Write-Host "  cd /mnt/c/Users/zjy/super-os/iso" -ForegroundColor White
Write-Host "  sudo bash build-iso.sh" -ForegroundColor White
Write-Host ""
