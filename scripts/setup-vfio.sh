#!/bin/bash
# Super-OS VFIO GPU Passthrough Setup
# 用途: 检测独显, 隔离到 vfio-pci, 配置 modprobe 和 initramfs
# 硬件: Intel Core Ultra 9 + Intel Arc iGPU (宿主) + 独显 (直通)

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; exit 1; }
info() { echo -e "${BLUE}[*]${NC} $*"; }

# ─── 检测是否为 root ───
if [[ $EUID -ne 0 ]]; then err "请用 sudo 运行此脚本"; fi

# ─── 步骤 1: 检测 IOMMU ───
log "检测 IOMMU 是否启用..."
if ! dmesg | grep -qi "iommu\|amd-vi\|vt-d"; then
    err "IOMMU 未启用! 请在 BIOS 中开启 Intel VT-d, 并在内核参数中添加 intel_iommu=on iommu=pt"
fi
log "IOMMU 已启用"

# ─── 步骤 2: 检测 GPU ───
log "扫描 GPU 设备..."
echo ""

declare -A GPU_MAP
GPU_COUNT=0
IGPU_PCI=""
DGPU_PCI=""
DGPU_AUDIO_PCI=""

while IFS= read -r line; do
    PCI=$(echo "$line" | awk '{print $1}')
    VEN_DEV=$(echo "$line" | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])')
    DESC=${line#*: }

    GPU_COUNT=$((GPU_COUNT + 1))
    GPU_MAP["gpu${GPU_COUNT}_pci"]="$PCI"
    GPU_MAP["gpu${GPU_COUNT}_vendor"]="$VEN_DEV"
    GPU_MAP["gpu${GPU_COUNT}_desc"]="$DESC"

    echo "  GPU $GPU_COUNT: $PCI - $VEN_DEV - $DESC"
done < <(lspci -nn | grep -i "vga\|3d\|display" | grep -v "Host bridge")

if [[ $GPU_COUNT -lt 2 ]]; then
    warn "只检测到 $GPU_COUNT 个 GPU。单卡需要方案 B (纯单卡切换)。"
    warn "如果你有 Intel 核显 + 独显, 请检查 BIOS 是否开启了 iGPU Always Enable"
    warn "如果你只有独显, 请使用 single-gpu-vfio.sh 脚本"
    exit 1
fi

echo ""
info "请确认哪个是你的独显 (要直通给 Windows VM):"
echo ""
for i in $(seq 1 $GPU_COUNT); do
    pci_var="gpu${i}_pci"
    ven_var="gpu${i}_vendor"
    desc_var="gpu${i}_desc"
    echo "  [$i] ${GPU_MAP[$pci_var]} - ${GPU_MAP[$ven_var]} - ${GPU_MAP[$desc_var]}"
done
echo ""
read -rp "输入独显编号 [1-$GPU_COUNT]: " GPU_CHOICE

DGPU_PCI="${GPU_MAP[gpu${GPU_CHOICE}_pci]}"
DGPU_VENDOR="${GPU_MAP[gpu${GPU_CHOICE}_vendor]}"
DGPU_DESC="${GPU_MAP[gpu${GPU_CHOICE}_desc]}"

log "选择: $DGPU_PCI ($DGPU_VENDOR)"

# ─── 步骤 3: 获取独显的完整 VFIO ID 列表 ───
log "分析 IOMMU 分组, 获取独显所有关联设备..."

IOMMU_GROUP=""
for group in /sys/kernel/iommu_groups/*/devices/*; do
    dev_pci=$(basename "$(readlink "$group")")
    if [[ "$dev_pci" == "$DGPU_PCI" ]]; then
        IOMMU_GROUP=$(echo "$group" | grep -oP 'iommu_groups/\K\d+')
        break
    fi
done

if [[ -z "$IOMMU_GROUP" ]]; then
    err "无法确定独显的 IOMMU 分组"
fi

log "独显在 IOMMU 组 $IOMMU_GROUP"

# 获取同组所有设备
VFIO_IDS=()
IOMMU_DEVS=()
for dev in /sys/kernel/iommu_groups/"$IOMMU_GROUP"/devices/*; do
    dev_pci=$(basename "$(readlink "$dev")")
    ven_dev=$(lspci -nns "$dev_pci" | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])')
    VFIO_IDS+=("$ven_dev")
    IOMMU_DEVS+=("$dev_pci")
    desc=$(lspci -s "$dev_pci" | cut -d' ' -f2-)
    echo "  $dev_pci - $ven_dev - $desc"
done

VFIO_STRING=$(IFS=,; echo "${VFIO_IDS[*]}")
log "VFIO 设备 ID 列表: $VFIO_STRING"

# ─── 步骤 4: 创建 modprobe 配置 ───
log "创建 VFIO modprobe 配置..."

cat > /etc/modprobe.d/vfio.conf << EOF
# Super-OS VFIO GPU Passthrough Configuration
# 独显: $DGPU_DESC
# IOMMU Group: $IOMMU_GROUP

# 强制 vfio-pci 在宿主驱动之前加载
softdep drm pre: vfio-pci
softdep nvidia pre: vfio-pci
softdep amdgpu pre: vfio-pci
softdep nouveau pre: vfio-pci
softdep radeon pre: vfio-pci

# vfio-pci 设备 ID
options vfio-pci ids=$VFIO_STRING
options vfio-pci disable_vga=1

# 禁用独显的 framebuffer 驱动
options vfio_iommu_type1 allow_unsafe_interrupts=1
EOF

log "已创建 /etc/modprobe.d/vfio.conf"

# ─── 步骤 5: 配置 initramfs (mkinitcpio) ───
log "配置 mkinitcpio..."

# 添加 vfio 模块到 initramfs
if ! grep -q "vfio" /etc/mkinitcpio.conf; then
    sed -i 's/^MODULES=(/MODULES=(vfio_pci vfio vfio_iommu_type1 vfio_virqfd /' /etc/mkinitcpio.conf
fi

# 确保 MODULES 行格式正确
sed -i 's/^MODULES=()/MODULES=(vfio_pci vfio vfio_iommu_type1 vfio_virqfd)/' /etc/mkinitcpio.conf

cat /etc/mkinitcpio.conf | grep "^MODULES="
log "重建 initramfs..."
mkinitcpio -P

# ─── 步骤 6: 创建 VFIO 验证脚本 ───
log "创建 VFIO 验证脚本..."

cat > /usr/local/bin/vfio-check << 'VFIOCHECK'
#!/bin/bash
echo "=== VFIO 状态检查 ==="
echo ""
echo "vfio-pci 加载的设备:"
lspci -k | grep -A 3 -i "vga\|3d" | grep -i "vfio\|kernel driver" || echo "  (无 - 重启后生效)"
echo ""
echo "IOMMU 分组:"
for d in /sys/kernel/iommu_groups/*/devices/*; do
    n=${d#*/iommu_groups/*}; n=${n%%/*}
    printf "  Group %-3s: %s\n" "$n" "$(lspci -nns "${d##*/}" | head -c 80)"
done
echo ""
echo "内核命令行:"
cat /proc/cmdline
echo ""
echo "HugePages:"
grep -i "huge" /proc/meminfo
VFIOCHECK
chmod +x /usr/local/bin/vfio-check

# ─── 步骤 7: 创建 Udev 规则 (可选, 进一步确保 vfio-pci 绑定) ───
cat > /etc/udev/rules.d/99-vfio-dgpu.rules << UDEVEOF
# Super-OS: 确保独显设备绑定 vfio-pci
$(for dev in "${IOMMU_DEVS[@]}"; do
    echo "SUBSYSTEM==\"pci\", ATTRS{vendor}==\"0x${VFIO_IDS[0]%:*}\", ATTRS{device}==\"0x${VFIO_IDS[0]#*:}\", ATTR{driver_override}=\"vfio-pci\""
done)
UDEVEOF

# ─── 步骤 8: 完成 ───
echo ""
log "==========================================================="
log " VFIO GPU 直通配置完成!"
log "==========================================================="
echo ""
info "下一步:"
info "  1. 重启系统: reboot"
info "  2. 验证 VFIO: vfio-check"
info "  3. 确认核显正常驱动 KDE 桌面"
info "  4. 确认独显已被 vfio-pci 接管"
info "  5. 运行 win11-vm.sh 创建/启动 Windows VM"
echo ""
warn "重要提醒:"
warn "  - 显示器必须接主板 DP/HDMI 口 (核显输出), 不能接独显口!"
warn "  - 如果重启后独显还在用宿主驱动, 检查 BIOS iGPU Multi-Monitor 选项"
warn "  - 如果 KDE 黑屏, 拔掉独显输出线, 确保只用核显输出"
echo ""
