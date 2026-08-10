#!/bin/bash
# Super-OS Waydroid Android Setup
# 在 Wayland 上运行 Android 容器, 独立窗口嵌入 KDE 桌面

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; exit 1; }

# ─── 安装 Waydroid ───
log "安装 Waydroid..."
if ! command -v yay &>/dev/null; then
    log "安装 yay (AUR helper)..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay-build
    cd /tmp/yay-build && makepkg -si --noconfirm
    cd - && rm -rf /tmp/yay-build
fi

yay -S --noconfirm waydroid

# ─── 初始化 Waydroid ───
log "初始化 Waydroid 容器..."
sudo waydroid init -s GAPPS -c https://ota.waydro.id/system

log "注册 Waydroid 内核模块..."
sudo modprobe binder_linux devices=binder,hwbinder,vndbinder
sudo modprobe ashmem_linux

# 持久化内核模块
echo "binder_linux" | sudo tee /etc/modules-load.d/waydroid.conf
echo "ashmem_linux" | sudo tee -a /etc/modules-load.d/waydroid.conf

# ─── 安装 ARM 翻译层 ───
log "安装 ARM 翻译层 (libhoudini for Intel)..."

# 从 Waydroid 镜像提取 libhoudini
HOUNDINI_URL="https://github.com/supremegamers/vendor_intel_proprietary_houdini/releases/download/11.0.1b_y.3879624136/houdini_y.sfs"

log "下载 libhoudini..."
wget -q "$HOUNDINI_URL" -O /tmp/houdini_y.sfs

# 挂载并复制
mkdir -p /tmp/houdini_mount
sudo mount -o loop /tmp/houdini_y.sfs /tmp/houdini_mount
sudo mkdir -p /var/lib/waydroid/overlay/system/lib64
sudo cp -r /tmp/houdini_mount/* /var/lib/waydroid/overlay/system/lib64/arm
sudo umount /tmp/houdini_mount

log "libhoudini 安装完成 (ARM → x86_64 翻译)"

# ─── 启动 Waydroid ───
log "启动 Waydroid 会话..."
waydroid session start &

sleep 5
waydroid show-full-ui &

# ─── 用户级自启动 ───
mkdir -p "$HOME/.config/systemd/user"

cat > "$HOME/.config/systemd/user/waydroid-container.service" << 'EOF'
[Unit]
Description=Waydroid Android Container
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/waydroid session start
ExecStop=/usr/bin/waydroid session stop
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

systemctl --user daemon-reload
systemctl --user enable waydroid-container.service

log "Waydroid 安装完成!"
echo ""
info "使用方法:"
info "  waydroid app list             列出已安装应用"
info "  waydroid app install x.apk    安装 APK"
info "  waydroid app launch <package> 启动应用"
info "  waydroid show-full-ui         显示完整 Android 界面"
echo ""
