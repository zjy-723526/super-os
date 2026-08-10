#!/bin/bash
# Super-OS Looking Glass Setup
# 编译安装 Looking Glass Client (Wayland 后端)
# Looking Glass = Windows VM 画面通过 IVSHMEM 共享内存传输到 Linux, <1ms 延迟

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; exit 1; }

LG_VERSION="B7"  # Looking Glass 版本

# ─── 安装依赖 ───
log "安装 Looking Glass 编译依赖..."
sudo pacman -S --needed \
    cmake gcc make pkg-config \
    wayland wayland-protocols \
    libx11 libxss libxrandr libxfixes \
    mesa glew glfw-x11 \
    freetype2 fontconfig \
    spice-protocol \
    pipewire \
    sdl2

# ─── 克隆并编译 ───
BUILD_DIR="$HOME/.cache/looking-glass-build"
log "克隆 Looking Glass (版本: $LG_VERSION)..."

rm -rf "$BUILD_DIR"
git clone --depth 1 --branch "$LG_VERSION" \
    https://github.com/gnif/LookingGlass.git "$BUILD_DIR"

cd "$BUILD_DIR/client"
mkdir -p build && cd build

log "配置 CMake (Wayland + EGL)..."
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_EGL=ON \
    -DENABLE_WAYLAND=ON \
    -DENABLE_X11=OFF \
    -DENABLE_PIPEWIRE=ON \
    -DENABLE_SPICE=ON

log "编译 (使用所有核心)..."
make -j"$(nproc)"

log "安装..."
sudo make install

# ─── 创建 Looking Glass 配置 ───
mkdir -p "$HOME/.looking-glass"

cat > "$HOME/.looking-glass/config.ini" << 'EOF'
[General]
title=Windows 11
fullScreen=no
borderless=yes
resizable=yes
keepAspect=yes

[Input]
autoCapture=yes
captureOnFocus=yes
escapeKey=97

[Wayland]
fractionalScaling=yes
useDMABUF=yes

[Spice]
enable=yes
host=127.0.0.1
port=5900
EOF

log "Looking Glass 安装完成!"
echo ""
info "使用方法:"
info "  looking-glass-client                    窗口模式"
info "  looking-glass-client -F                 全屏模式"
info "  looking-glass-client -F -M              全屏 + 相对鼠标 (FPS)"
info "  looking-glass-client -f /dev/shm/looking-glass  指定共享内存路径"
echo ""
info "快捷键:"
info "  ScrollLock          释放/捕获 键盘"
info "  Ctrl+Alt+F          切换全屏"
info "  Ctrl+Alt+V          切换显示/隐藏"
info "  Ctrl+Alt+I          显示 FPS 信息"
