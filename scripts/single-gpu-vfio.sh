#!/bin/bash
# Super-OS 单卡 VFIO 切换脚本 (方案 B 备选)
# 用于没有核显的用户: 独显在 Linux 和 Windows VM 之间自动切换
# 使用: sudo bash single-gpu-vfio.sh start    (切换到 Windows)
#       sudo bash single-gpu-vfio.sh stop     (归还 GPU 给 Linux)

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; exit 1; }
info() { echo -e "${BLUE}[*]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then err "请用 sudo 运行"; fi

# ─── 配置 (修改为你的硬件!) ───
GPU_PCI="01:00.0"
GPU_AUDIO_PCI="01:00.1"
GPU_DRIVER="nvidia"  # nvidia / amdgpu / nouveau / radeon
GPU_DRIVER_MODS="${GPU_DRIVER} ${GPU_DRIVER}_drm ${GPU_DRIVER}_modeset ${GPU_DRIVER}_uvm"
DM_SERVICE="sddm"
VM_NAME="win11"

# ─── 获取当前 VT 和显示信息 ───
CURRENT_VT=$(fgconsole 2>/dev/null || echo 1)

# ─── 函数: 停止 Linux GPU ───
stop_linux_gpu() {
    log "停止 Linux 图形服务..."

    # 保存当前状态 (可选)
    loginctl list-sessions

    # 停止 SDDM
    systemctl stop "$DM_SERVICE"

    # 等待所有 GPU 进程结束
    sleep 2
    for attempt in {1..5}; do
        GPU_USERS=$(lsof /dev/dri/* 2>/dev/null | grep -v "COMMAND" || true)
        if [[ -z "$GPU_USERS" ]]; then
            break
        fi
        warn "等待 GPU 释放... (尝试 $attempt/5)"
        sleep 1
    done

    # 卸载 GPU 驱动模块
    log "卸载 GPU 驱动: $GPU_DRIVER_MODS"
    for mod in $GPU_DRIVER_MODS; do
        modprobe -r "$mod" 2>/dev/null || warn "无法卸载 $mod (可能未加载)"
    done

    # 释放 VT 控制台
    echo 0 > /sys/class/vtconsole/vtcon0/bind 2>/dev/null || true
    echo 0 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true
    echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind 2>/dev/null || true

    log "GPU 已从 Linux 释放"
}

# ─── 函数: 绑定 GPU 到 vfio-pci ───
bind_gpu_to_vfio() {
    log "绑定 GPU 到 vfio-pci..."

    # 确保 vfio-pci 已加载
    modprobe vfio-pci

    # 解绑当前驱动
    for dev in "$GPU_PCI" "$GPU_AUDIO_PCI"; do
        echo "$dev" > "/sys/bus/pci/devices/0000:${dev}/driver/unbind" 2>/dev/null || true
    done

    # 绑定到 vfio-pci
    for dev in "$GPU_PCI" "$GPU_AUDIO_PCI"; do
        VEN_DEV=$(lspci -nns "$dev" | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])')
        echo "$VEN_DEV" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true
        echo "0000:$dev" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true
    done

    log "GPU 已绑定到 vfio-pci"
}

# ─── 函数: 归还 GPU 给 Linux ───
restore_gpu_to_linux() {
    log "归还 GPU 给 Linux..."

    # 从 vfio-pci 解绑
    for dev in "$GPU_PCI" "$GPU_AUDIO_PCI"; do
        echo "0000:$dev" > /sys/bus/pci/drivers/vfio-pci/unbind 2>/dev/null || true
    done

    # 重新绑定 framebuffer
    echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/bind 2>/dev/null || true
    echo 1 > /sys/class/vtconsole/vtcon0/bind 2>/dev/null || true
    echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true

    # 加载 GPU 驱动
    log "加载 GPU 驱动..."
    for mod in $GPU_DRIVER_MODS; do
        modprobe "$mod" 2>/dev/null || warn "无法加载 $mod"
    done

    # 重启显示管理器
    systemctl start "$DM_SERVICE"

    log "GPU 已归还给 Linux!"
}

# ─── 主逻辑 ───
case "${1:-}" in
    start)
        log "=========================================="
        log " 单卡 VFIO 切换: GPU → Windows VM"
        log "=========================================="
        log "Linux 桌面将暂时不可用!"
        log "VM 关闭后 GPU 自动归还 Linux"
        echo ""

        stop_linux_gpu
        bind_gpu_to_vfio

        log "启动 Windows 11 VM..."
        virsh start "$VM_NAME" 2>/dev/null || {
            # 如果用 qemu 命令行
            bash "$(dirname "$0")/win11-vm.sh" --game
        }

        # 等待 VM 关闭
        info "等待 VM 关闭..."
        while virsh domstate "$VM_NAME" 2>/dev/null | grep -q "running"; do
            sleep 2
        done

        log "VM 已关闭, 归还 GPU 给 Linux..."
        restore_gpu_to_linux
        log "单卡切换完成! Linux 桌面已恢复"
        ;;

    stop)
        log "强制关闭 VM 并归还 GPU..."
        virsh shutdown "$VM_NAME" 2>/dev/null || virsh destroy "$VM_NAME" 2>/dev/null || true
        sleep 5
        restore_gpu_to_linux
        ;;

    status)
        echo "=== 单卡 VFIO 状态 ==="
        echo "GPU: $GPU_PCI"
        GPU_DRV=$(lspci -ks "$GPU_PCI" | grep "Kernel driver" | awk '{print $NF}')
        echo "当前驱动: ${GPU_DRV:-未知}"
        echo ""
        if [[ "$GPU_DRV" == "vfio-pci" ]]; then
            echo "GPU 已隔离 → Windows VM 可使用"
        else
            echo "GPU 在 Linux 宿主 → 正常模式"
        fi
        ;;

    *)
        echo "用法: $0 {start|stop|status}"
        echo ""
        echo "  start   停止 Linux 图形, GPU 直通给 Windows VM"
        echo "  stop    归还 GPU 给 Linux, 恢复桌面"
        echo "  status  查看当前 GPU 状态"
        exit 1
        ;;
esac
