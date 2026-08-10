#!/bin/bash
# Super-OS Docker Builder
# 在 Windows/Mac/Linux 上用 Docker 构建 ISO (不需要 WSL)
# 前提: 已安装 Docker Desktop 并正在运行

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; exit 1; }
info() { echo -e "${BLUE}[*]${NC} $*"; }

# Check Docker
if ! docker info &>/dev/null; then
    err "Docker 未运行! 请先启动 Docker Desktop"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"

log "项目目录: $PROJECT_DIR"

# Build in Docker
log "启动 Arch Linux 容器并构建 ISO..."

docker run --rm --privileged \
    -v "$PROJECT_DIR:/super-os" \
    -v "$OUTPUT_DIR:/output" \
    archlinux:latest \
    bash -c '
        set -e
        echo "[+] 配置镜像源..."
        echo "Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist

        echo "[+] 安装依赖..."
        pacman -Sy --noconfirm archiso git

        echo "[+] 构建 ISO..."
        cd /super-os/iso
        bash build-iso.sh /output

        echo "[+] 完成!"
    '

log "ISO 已输出到: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"/*.iso 2>/dev/null || warn "未找到 ISO 文件"
