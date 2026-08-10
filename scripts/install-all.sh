#!/bin/bash
# Super-OS 一键集成安装脚本
# 安装所有组件并配置系统集成

set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
info() { echo -e "${BLUE}[*]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/super-os"

# ─── 创建目录 ───
mkdir -p "$BIN_DIR" "$CONFIG_DIR"

# ─── 安装系统级配置 ───
log "安装系统级配置..."

# Udev 规则
sudo cp "$SCRIPT_DIR/../configs/udev/99-vfio-dgpu.rules" /etc/udev/rules.d/ 2>/dev/null || true

# Modprobe 配置
sudo cp "$SCRIPT_DIR/../configs/modprobe/vfio.conf" /etc/modprobe.d/vfio-enabled.conf 2>/dev/null || true

# Sysctl 配置
sudo cp "$SCRIPT_DIR/../configs/sysctl/99-superos.conf" /etc/sysctl.d/ 2>/dev/null || true

# ─── 安装用户脚本 ───

# Windows VM 启动器
cat > "$BIN_DIR/start-windows" << 'STARTWIN'
#!/bin/bash
# 启动 Windows 11 VM + Looking Glass
bash ~/super-os/scripts/win11-vm.sh &
sleep 15
looking-glass-client &
STARTWIN
chmod +x "$BIN_DIR/start-windows"

# 游戏模式
cat > "$BIN_DIR/game-mode" << 'GAMEMODE'
#!/bin/bash
# 全屏游戏模式
echo "进入游戏模式..."
echo "  ScrollLock: 释放键盘回 Linux"
echo "  Ctrl+Alt+F: 退出全屏"
gamemoderun bash ~/super-os/scripts/win11-vm.sh --game
GAMEMODE
chmod +x "$BIN_DIR/game-mode"

# 启动所有服务
cat > "$BIN_DIR/start-all" << 'STARTALL'
#!/bin/bash
echo "=== Super-OS 启动 ==="

# Waydroid
echo "[1/3] 启动 Waydroid..."
waydroid session start &

# Windows VM
echo "[2/3] 启动 Windows 11 VM..."
bash ~/super-os/scripts/win11-vm.sh --headless &
WIN_PID=$!

# Looking Glass
echo "[3/3] 启动 Looking Glass..."
sleep 20  # 等 Windows 启动完毕
looking-glass-client &

echo "Super-OS 启动完毕!"
echo "  - Windows 11: Looking Glass 窗口中"
echo "  - Android:    应用启动器中"

wait $WIN_PID
STARTALL
chmod +x "$BIN_DIR/start-all"

# 剪贴板同步
cat > "$BIN_DIR/clipboard-sync" << 'CLIPSYNC'
#!/bin/bash
# 双向剪贴板同步 (Linux ↔ Windows)
# 通过 SPICE vdagent 实现
if pgrep -x "spice-vdagent" > /dev/null; then
    echo "SPICE vdagent 已运行, 剪贴板自动同步中"
else
    spice-vdagent &
    echo "SPICE vdagent 已启动, 剪贴板同步中"
fi
CLIPSYNC
chmod +x "$BIN_DIR/clipboard-sync"

# ─── 系统服务 ───
log "安装 systemd 用户服务..."

# Windows VM 自启动服务
cat > "$HOME/.config/systemd/user/win11-vm.service" << 'WINSVC'
[Unit]
Description=Windows 11 Virtual Machine
After=network.target libvirtd.service
Requires=libvirtd.service

[Service]
Type=simple
ExecStart=%h/.local/bin/start-windows
ExecStop=/usr/bin/virsh shutdown win11
Restart=no

[Install]
WantedBy=default.target
WINSVC

systemctl --user daemon-reload
log "用户服务已安装 (未启用自启动, 手动启用: systemctl --user enable win11-vm)"

# ─── KDE 集成 ───
log "安装 KDE 桌面集成..."

# 应用启动器 .desktop 文件
mkdir -p "$HOME/.local/share/applications"

cat > "$HOME/.local/share/applications/superos-windows.desktop" << 'WINDESKTOP'
[Desktop Entry]
Name=Windows 11
GenericName=Windows Virtual Machine
Comment=Launch Windows 11 VM with Looking Glass
Exec=/bin/bash -c "start-windows"
Icon=computer
Terminal=false
Type=Application
Categories=System;
Keywords=windows;vm;virtual;
StartupWMClass=looking-glass-client
WINDESKTOP

cat > "$HOME/.local/share/applications/superos-gamemode.desktop" << 'GAMEDESKTOP'
[Desktop Entry]
Name=Game Mode
GenericName=Windows Gaming Mode
Comment=Fullscreen Windows 11 for AAA Gaming
Exec=/bin/bash -c "game-mode"
Icon=applications-games
Terminal=true
Type=Application
Categories=Game;
Keywords=game;gaming;fullscreen;
GAMEDESKTOP

cat > "$HOME/.local/share/applications/superos-waydroid.desktop" << 'ANDROIDDESKTOP'
[Desktop Entry]
Name=Android (Waydroid)
GenericName=Android Container
Comment=Launch Android apps via Waydroid
Exec=/usr/bin/waydroid show-full-ui
Icon=phone
Terminal=false
Type=Application
Categories=System;
Keywords=android;waydroid;apk;
ANDROIDDESKTOP

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# ─── 完成 ───
echo ""
log "=========================================="
log " Super-OS 集成安装完成!"
log "=========================================="
echo ""
info "已安装的快捷命令:"
info "  start-all         启动所有服务 (VM + LookingGlass + Waydroid)"
info "  start-windows     启动 Windows 11 + Looking Glass"
info "  game-mode         全屏游戏模式"
info "  clipboard-sync    剪贴板同步"
echo ""
info "已安装的桌面快捷方式:"
info "  Windows 11        (应用启动器)"
info "  Game Mode         (应用启动器)"
info "  Android           (应用启动器)"
echo ""
info "可选: 启用开机自启动"
info "  systemctl --user enable win11-vm"
echo ""
