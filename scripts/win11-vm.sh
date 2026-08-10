#!/bin/bash
# Super-OS Windows 11 VM Launcher
# Intel Core Ultra 9 + VFIO GPU Passthrough + Looking Glass + IVSHMEM
# 用法:
#   win11-vm.sh                   日常模式 (SPICE 窗口)
#   win11-vm.sh --install         首次安装 Windows
#   win11-vm.sh --game            游戏模式 (evdev 直通 + Looking Glass 全屏)
#   win11-vm.sh --headless        无头模式 (只启动 VM, 不显示)

set -euo pipefail

# ─── 配置 (请根据你的硬件修改!) ───
VM_NAME="win11"
VM_DIR="/var/lib/libvirt/images"
VM_DISK="${VM_DIR}/win11.qcow2"
WIN11_ISO="${VM_DIR}/Win11.iso"
VIRTIO_ISO="${VM_DIR}/virtio-win.iso"

# CPU 配置 (Intel Core Ultra 9)
HOST_CORES=24          # 总核心数
VM_CORES=16            # 给 VM 的核心
VM_SOCKETS=1
VM_THREADS=2

# 内存配置
VM_MEM_GB=32
VM_MEM_MB=$((VM_MEM_GB * 1024))

# GPU 直通 (修改为你的独显 PCI 地址!)
GPU_PCI="01:00.0"      # 独显 VGA
GPU_AUDIO_PCI="01:00.1" # 独显 HDMI/DP 音频

# Looking Glass
LG_SHM_SIZE="64M"      # 共享内存大小 (4K: 32M, 1080p: 64M, 1440p: 128M, 4K: 256M)
LG_SHM_PATH="/dev/shm/looking-glass"

# 输入设备 (evdev 直通, 用 ls /dev/input/by-id/ 查找)
KBD_DEV="/dev/input/by-id/usb-Your_Keyboard-event-kbd"
MSE_DEV="/dev/input/by-id/usb-Your_Mouse-event-mouse"

# 音频
AUDIO_DEV="intel-hda"

# OVMF UEFI
OVMF_CODE="/usr/share/edk2-ovmf/x64/OVMF_CODE.fd"
OVMF_VARS="/var/lib/libvirt/qemu/nvram/win11_VARS.fd"

# ─── 颜色输出 ───
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
info() { echo -e "${BLUE}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; exit 1; }

# ─── 参数解析 ───
MODE="normal"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)  MODE="install"; shift ;;
        --game)     MODE="game"; shift ;;
        --headless) MODE="headless"; shift ;;
        --help|-h)  echo "用法: $0 [--install|--game|--headless]"; exit 0 ;;
        *) err "未知参数: $1" ;;
    esac
done

# ─── 前置检查 ───

# 检查 vfio-pci 是否加载
if ! lsmod | grep -q vfio_pci; then
    warn "vfio-pci 模块未加载, 直通可能失败"
fi

# 检查 HugePages
HUGEPAGES=$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo 0)
if [[ $HUGEPAGES -eq 0 ]]; then
    warn "HugePages 未配置, 运行 setup-hugepages.sh 获得最佳性能"
fi

# 确保 OVMF VARS 存在
if [[ ! -f "$OVMF_VARS" ]]; then
    log "初始化 OVMF VARS..."
    mkdir -p "$(dirname "$OVMF_VARS")"
    cp "$OVMF_CODE" "$OVMF_VARS"
fi

# ─── 基础 QEMU 参数 ───
QEMU_BIN="qemu-system-x86_64"

# 基础机器参数
BASE_ARGS=(
    -name "$VM_NAME,debug-threads=on"
    -machine type=q35,accel=kvm,kernel_irqchip=on
    -global kvm-pit.lost_tick_policy=delay
)

# CPU 参数 - Intel Core Ultra 9 优化
CPU_ARGS=(
    -cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time
    -smp $VM_CORES,sockets=$VM_SOCKETS,cores=$((VM_CORES/VM_THREADS)),threads=$VM_THREADS
)

# 内存参数 - 大页 + 预分配
MEM_ARGS=(
    -m ${VM_MEM_MB}M
    -mem-prealloc
    -overcommit mem-lock=on
    -object "memory-backend-file,id=mem,size=${VM_MEM_MB}M,mem-path=/dev/hugepages,share=on,prealloc=yes"
    -numa node,memdev=mem
)

# OVMF UEFI
BIOS_ARGS=(
    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}"
    -drive "if=pflash,format=raw,file=${OVMF_VARS}"
)

# 系统盘
DISK_ARGS=(
    -drive "file=${VM_DISK},if=virtio,cache=none,aio=native,discard=unmap,detect-zeroes=unmap"
)

# ─── GPU 直通参数 ───
GPU_ARGS=(
    -device "vfio-pci,host=${GPU_PCI},multifunction=on,x-vga=on,rombar=1"
    -device "vfio-pci,host=${GPU_AUDIO_PCI}"
)

# ─── Looking Glass IVSHMEM ───
LG_ARGS=(
    -device "ivshmem-plain,memdev=ivshmem"
    -object "memory-backend-file,id=ivshmem,share=on,mem-path=${LG_SHM_PATH},size=${LG_SHM_SIZE}"
)

# ─── SPICE 参数 (日常模式) ───
SPICE_ARGS=(
    -spice "port=5900,addr=127.0.0.1,disable-ticketing=on,seamless-migration=on"
    -device virtio-serial-pci
    -chardev "spicevmc,id=vdagent,name=vdagent"
    -device "virtserialport,chardev=vdagent,name=com.redhat.spice.0"
)

# ─── 音频 ───
AUDIO_ARGS=(
    -audiodev "pa,id=audio1,server=unix:/run/user/1000/pulse/native"
    -device "${AUDIO_DEV},audiodev=audio1"
)

# ─── 网络 ───
NET_ARGS=(
    -netdev "user,id=net0,hostfwd=tcp::3389-:3389"
    -device "virtio-net-pci,netdev=net0"
)

# ─── 输入 ───
INPUT_ARGS=(
    -device virtio-keyboard-pci
    -device virtio-mouse-pci
)

# ─── 杂项 (隐藏 VM 特征) ───
MISC_ARGS=(
    -smbios "type=0,uefi=on"
    -smbios "type=1,manufacturer=ASUS,product=ROG-MAXIMUS,version=System Version,serial=System Serial,sku=SKU"
    -smbios "type=2,manufacturer=ASUS,product=ROG-MAXIMUS,version=Rev 1.xx"
    -smbios "type=3,manufacturer=ASUS,version=Rev 1.xx"
    -rtc "base=localtime,driftfix=slew"
    -global "ICH9-LPC.disable_s3=1"
    -no-hpet
)

# ─── TPM 2.0 (Win11 要求) ───
TPM_ARGS=(
    -tpmdev "swtpm,id=tpm0"
    -device "tpm-tis,tpmdev=tpm0"
)

# ─── 组合参数 ───
MAIN_ARGS=(
    "${BASE_ARGS[@]}"
    "${CPU_ARGS[@]}"
    "${MEM_ARGS[@]}"
    "${BIOS_ARGS[@]}"
    "${DISK_ARGS[@]}"
    "${GPU_ARGS[@]}"
    "${LG_ARGS[@]}"
    "${AUDIO_ARGS[@]}"
    "${NET_ARGS[@]}"
    "${MISC_ARGS[@]}"
    "${TPM_ARGS[@]}"
)

# ─── 模式特定参数 ───
case "$MODE" in
    install)
        log "=== 安装模式: Windows 11 首次安装 ==="
        INSTALL_ARGS=(
            "${MAIN_ARGS[@]}"
            -cdrom "$WIN11_ISO"
            -drive "file=${VIRTIO_ISO},media=cdrom"
            -boot order=d
            "${INPUT_ARGS[@]}"
            -vga qxl
            -display gtk,gl=on
        )
        $QEMU_BIN "${INSTALL_ARGS[@]}"
        ;;

    normal)
        log "=== 日常模式: SPICE + Looking Glass ==="
        info "SPICE 端口: 127.0.0.1:5900"
        info "启动 Looking Glass 查看 Windows 桌面: looking-glass-client"
        NORMAL_ARGS=(
            "${MAIN_ARGS[@]}"
            "${SPICE_ARGS[@]}"
            "${INPUT_ARGS[@]}"
            -display spice-app
        )
        $QEMU_BIN "${NORMAL_ARGS[@]}" &
        VM_PID=$!
        log "VM PID: $VM_PID"
        info "使用 'remote-viewer spice://127.0.0.1:5900' 连接 (剪贴板同步)"
        info "或直接启动 looking-glass-client 获得零延迟画面"
        wait $VM_PID
        ;;

    game)
        log "=== 游戏模式: evdev 直通 + Looking Glass ==="
        # 检查 evdev 设备
        if [[ ! -e "$KBD_DEV" ]]; then
            warn "键盘设备 $KBD_DEV 未找到, 使用默认输入"
            KBD_EVDEV=""
        else
            KBD_EVDEV="-object input-linux,id=kbd,evdev=${KBD_DEV},grab_all=on"
        fi
        if [[ ! -e "$MSE_DEV" ]]; then
            warn "鼠标设备 $MSE_DEV 未找到, 使用默认输入"
            MSE_EVDEV=""
        else
            MSE_EVDEV="-object input-linux,id=mouse,evdev=${MSE_DEV}"
        fi

        GAME_ARGS=(
            "${MAIN_ARGS[@]}"
            $KBD_EVDEV
            $MSE_EVDEV
            -display none
        )
        log "启动 VM (无显示输出)..."
        $QEMU_BIN "${GAME_ARGS[@]}" &
        VM_PID=$!

        sleep 10
        log "启动 Looking Glass 全屏..."
        looking-glass-client -F -M -m 97 -f "$LG_SHM_PATH"

        # VM 关闭后清理
        kill $VM_PID 2>/dev/null || true
        log "游戏模式结束"
        ;;

    headless)
        log "=== 无头模式 ==="
        HEADLESS_ARGS=(
            "${MAIN_ARGS[@]}"
            -display none
        )
        $QEMU_BIN "${HEADLESS_ARGS[@]}"
        ;;
esac
