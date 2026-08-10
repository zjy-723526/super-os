#!/bin/bash
# Super-OS ISO Builder
# 在 Arch Linux (WSL2/VM/实体机) 上运行此脚本
# 用法: sudo bash build-iso.sh

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; exit 1; }
info() { echo -e "${BLUE}[*]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then err "请用 sudo bash build-iso.sh 运行"; fi

# ─── 检查依赖 ───
log "检查构建依赖..."
pacman -Sy --noconfirm --needed archiso git base-devel

if ! command -v mkarchiso &>/dev/null; then
    err "mkarchiso 未找到, 安装 archiso 失败"
fi
log "archiso $(mkarchiso --version 2>/dev/null || echo 'OK')"

# ─── 目录设置 ───
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR/profile"
OUTPUT_DIR="${1:-$SCRIPT_DIR/output}"
WORK_DIR="/tmp/super-os-iso-work"

log "Profile: $PROFILE_DIR"
log "输出:    $OUTPUT_DIR"

# ─── 清理旧构建 ───
log "清理旧构建..."
rm -rf "$WORK_DIR" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ─── 同步脚本和配置到 airootfs ───
log "同步 Super-OS 文件到 ISO profile..."

SRC="$SCRIPT_DIR/.."

# 确保 target 目录存在
for d in \
    "$PROFILE_DIR/airootfs/root/super-os/scripts" \
    "$PROFILE_DIR/airootfs/root/super-os/configs/modprobe" \
    "$PROFILE_DIR/airootfs/root/super-os/configs/sysctl" \
    "$PROFILE_DIR/airootfs/root/super-os/configs/qemu" \
    "$PROFILE_DIR/airootfs/root/super-os/configs/kde"; do
    mkdir -p "$d"
done

cp_files() {
    local src="$SRC/$1"
    local dst="$PROFILE_DIR/airootfs/root/super-os/$1"
    if [[ -f "$src" ]]; then
        cp "$src" "$dst"
        info "  $1"
    else
        warn "  跳过 (缺失): $1"
    fi
}

# 核心脚本
for s in setup-vfio setup-hugepages setup-looking-glass setup-waydroid \
         win11-vm single-gpu-vfio install-all; do
    cp_files "scripts/${s}.sh"
done

# 配置文件
for c in \
    "configs/sysctl/99-superos.conf" \
    "configs/qemu/win11-libvirt.xml" \
    "configs/kde/kwin-rules.kwinrule" \
    "configs/kde/virtual-desktops.sh"; do
    cp_files "$c"
done

# 文档
cp_files "README.md"
cp_files "install-guide.md"

# 设置权限
chmod -R 755 "$PROFILE_DIR/airootfs/root/super-os/scripts/"
log "同步完成 ($(find $PROFILE_DIR/airootfs/root/super-os -type f | wc -l) 个文件)"

# ─── 构建 ISO ───
echo ""
log "=========================================="
log " 开始构建 Super-OS ISO"
log "=========================================="
info "这需要 10-30 分钟 (取决于网络速度和 CPU)"
info "ISO 将包含: KDE Plasma + QEMU + NVIDIA/AMD/Intel 驱动 + 全部脚本"
echo ""

START_TIME=$(date +%s)

cd "$PROFILE_DIR"
mkarchiso -v -w "$WORK_DIR" -o "$OUTPUT_DIR" .

END_TIME=$(date +%s)
BUILD_TIME=$((END_TIME - START_TIME))

# ─── 完成 ───
echo ""
log "=========================================="
log " 构建完成! (耗时: ${BUILD_TIME}秒)"
log "=========================================="
echo ""

ISO_FILE=$(ls -t "$OUTPUT_DIR"/*.iso 2>/dev/null | head -1)
if [[ -n "$ISO_FILE" ]]; then
    ISO_SIZE=$(du -h "$ISO_FILE" | cut -f1)
    log "✅ ISO: $ISO_FILE"
    log "📦 大小: $ISO_SIZE"
    echo ""
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info " 接下来:"
    info "  1. 用 Rufus 或 Ventoy 写入 U 盘"
    info "  2. 从 U 盘启动 → Super-OS Live 桌面"
    info "  3. Calamares 图形安装器自动弹出"
    info "  4. 选择磁盘 → 安装 → 重启"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    err "ISO 构建失败! 未找到输出文件"
fi

# 清理
rm -rf "$WORK_DIR"
log "工作目录已清理"
