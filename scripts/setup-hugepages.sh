#!/bin/bash
# Super-OS HugePages Setup
# 为大页内存配置, 提升 VM 游戏性能

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; exit 1; }

if [[ $EUID -ne 0 ]]; then err "请用 sudo 运行"; fi

# ─── 获取系统内存 ───
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))

echo "系统内存: ${TOTAL_MEM_GB} GB"
echo ""

# ─── HugePage 大小 ───
read -rp "分配给 Windows VM 的内存 (GB) [16]: " VM_MEM_GB
VM_MEM_GB=${VM_MEM_GB:-16}

if [[ $VM_MEM_GB -ge $TOTAL_MEM_GB ]]; then
    err "VM 内存不能大于或等于系统总内存!"
fi

# 计算 2MB HugePages 数量 + 10% buffer
HUGEPAGES_2M=$(( (VM_MEM_GB * 1024 / 2) + (VM_MEM_GB * 1024 / 2 / 10) ))

log "需要 ${VM_MEM_GB}GB 给 VM, 计算 HugePages: ${HUGEPAGES_2M} x 2MB"

# ─── 配置 HugePages ───
log "配置 HugePages..."

# 立即生效
echo "$HUGEPAGES_2M" > /proc/sys/vm/nr_hugepages

# 持久化
cat > /etc/sysctl.d/99-hugepages.conf << EOF
# Super-OS HugePages Configuration
# VM 内存: ${VM_MEM_GB} GB
vm.nr_hugepages=$HUGEPAGES_2M
EOF

# 确保 hugetlbfs 挂载
if ! grep -q "/dev/hugepages" /etc/fstab; then
    echo "hugetlbfs /dev/hugepages hugetlbfs mode=1770,gid=kvm 0 0" >> /etc/fstab
    mkdir -p /dev/hugepages
    mount /dev/hugepages
fi

# 验证
NR_HUGE=$(cat /proc/sys/vm/nr_hugepages)
HUGEPAGE_SIZE=$(grep Hugepagesize /proc/meminfo | awk '{print $2}')
HUGEPAGE_TOTAL_KB=$((NR_HUGE * HUGEPAGE_SIZE))
HUGEPAGE_TOTAL_GB=$((HUGEPAGE_TOTAL_KB / 1024 / 1024))

log "HugePages 配置完成: ${NR_HUGE} x ${HUGEPAGE_SIZE}KB = ${HUGEPAGE_TOTAL_GB}GB"

# ─── CPU 隔离建议 ───
echo ""
log "CPU 核心隔离 (推荐, 但高级操作)"
echo "  为获得最佳游戏性能, 建议用 isolcpus 隔离部分 CPU 核心给 VM"
echo "  编辑 /etc/kernel/cmdline 添加:"
echo "  isolcpus=8-15 (隔离核心 8-15 给 Windows VM)"
echo "  你的 Core Ultra 9 CPU 建议隔离 8 个大核给 VM"
echo ""

log "HugePages 配置完成!"
