#!/bin/bash
# Super-OS Disk Installer
# 从 Live ISO 安装 Super-OS 到硬盘
# 包含完整的分区、格式化、安装、配置流程

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; exit 1; }
info() { echo -e "${BLUE}[*]${NC} $*"; }
title(){ echo -e "\n${CYAN}========================================${NC}"; echo -e "${CYAN} $*${NC}"; echo -e "${CYAN}========================================${NC}\n"; }

# ─── 欢迎 ───
clear
title "Super-OS Installer"
echo "  Windows 11 VM + Android 全兼容 Linux 发行版"
echo "  Intel Core Ultra 9 | KDE Plasma | GPU Passthrough"
echo ""

# ─── 检测启动模式 ───
if [[ -d /sys/firmware/efi ]]; then
    BOOT_MODE="uefi"
    log "检测到 UEFI 启动模式"
else
    BOOT_MODE="bios"
    err "仅支持 UEFI 启动! 请在 BIOS 中关闭 CSM/Legacy Boot"
fi

# ─── 选择目标磁盘 ───
echo ""
info "可用的磁盘:"
lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -v "loop\|sr" | head -20
echo ""
read -rp "输入目标磁盘 (例: nvme0n1, sda): " DISK

DISK_PATH="/dev/$DISK"
if [[ ! -b "$DISK_PATH" ]]; then
    err "磁盘 $DISK_PATH 不存在!"
fi

echo ""
warn "即将抹除 $DISK_PATH 上的所有数据!"
info "磁盘信息:"
lsblk "$DISK_PATH"
echo ""
read -rp "输入 YES 确认: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
    err "已取消"
fi

# ─── 分区 ───
title "Step 1/7: 分区"

if [[ "$DISK" == nvme* ]]; then
    PART1="${DISK_PATH}p1"
    PART2="${DISK_PATH}p2"
else
    PART1="${DISK_PATH}1"
    PART2="${DISK_PATH}2"
fi

log "创建分区表 (GPT)..."
parted "$DISK_PATH" mklabel gpt

log "创建 EFI 分区 (512 MiB)..."
parted "$DISK_PATH" mkpart primary fat32 1MiB 513MiB
parted "$DISK_PATH" set 1 esp on

log "创建根分区 (剩余空间, Btrfs)..."
parted "$DISK_PATH" mkpart primary btrfs 513MiB 100%

partprobe "$DISK_PATH"
sleep 2

# ─── 格式化 ───
title "Step 2/7: 格式化"

log "格式化 EFI 分区..."
mkfs.fat -F32 "$PART1"

log "格式化根分区 (Btrfs)..."
mkfs.btrfs -f "$PART2"

log "创建 Btrfs 子卷..."
mount "$PART2" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var
umount /mnt

log "挂载子卷..."
mount -o compress=zstd,subvol=@ "$PART2" /mnt
mkdir -p /mnt/{boot,home,.snapshots,var}
mount -o compress=zstd,subvol=@home "$PART2" /mnt/home
mount -o compress=zstd,subvol=@snapshots "$PART2" /mnt/.snapshots
mount -o compress=zstd,subvol=@var "$PART2" /mnt/var
mount "$PART1" /mnt/boot

# ─── 安装系统 ───
title "Step 3/7: 安装系统包"

log "复制 Live 环境包到目标磁盘..."
# 复制 live 环境的包缓存
pacstrap -G /mnt base linux-zen linux-zen-headers linux-firmware intel-ucode btrfs-progs sudo vim git curl wget networkmanager efibootmgr

# 安装完整 Super-OS 包集
log "安装 Super-OS 完整包集..."
cp /root/super-os/iso/profile/packages.x86_64 /mnt/root/packages.x86_64
pacstrap /mnt $(grep -v '^#' /mnt/root/packages.x86_64 | grep -v '^$' | tr '\n' ' ')

# ─── 配置系统 ───
title "Step 4/7: 配置系统"

log "生成 fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

log "设置时区..."
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
arch-chroot /mnt hwclock --systohc

log "设置 Locale..."
cat > /mnt/etc/locale.gen << 'LOC'
en_US.UTF-8 UTF-8
zh_CN.UTF-8 UTF-8
LOC
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

log "设置主机名..."
echo "super-os" > /mnt/etc/hostname
cat > /mnt/etc/hosts << 'HOSTS'
127.0.0.1   localhost
::1         localhost
127.0.1.1   super-os.localdomain  super-os
HOSTS

log "设置 root 密码..."
info "请设置 root 密码:"
arch-chroot /mnt passwd

log "创建用户..."
read -rp "输入用户名 [zjy]: " USERNAME
USERNAME=${USERNAME:-zjy}
arch-chroot /mnt useradd -m -G wheel,users,audio,video,storage,kvm,libvirt,input -s /bin/bash "$USERNAME"
info "请设置 $USERNAME 的密码:"
arch-chroot /mnt passwd "$USERNAME"
echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel

# ─── Bootloader ───
title "Step 5/7: 安装引导器"

ROOT_UUID=$(blkid -s UUID -o value "$PART2")

log "安装 systemd-boot..."
arch-chroot /mnt bootctl --path=/boot install

cat > /mnt/boot/loader/loader.conf << 'LDR'
default super-os.conf
timeout 3
console-mode max
editor no
LDR

cat > /mnt/boot/loader/entries/super-os.conf << BOOT
title   Super-OS
linux   /vmlinuz-linux-zen
initrd  /intel-ucode.img
initrd  /initramfs-linux-zen.img
options root=UUID=$ROOT_UUID rootflags=subvol=@ rw quiet intel_iommu=on iommu=pt
BOOT

cat > /mnt/boot/loader/entries/super-os-fallback.conf << BOOTF
title   Super-OS (fallback)
linux   /vmlinuz-linux-zen
initrd  /intel-ucode.img
initrd  /initramfs-linux-zen-fallback.img
options root=UUID=$ROOT_UUID rootflags=subvol=@ rw intel_iommu=on iommu=pt
BOOTF

# ─── 复制 Super-OS 脚本到目标系统 ───
title "Step 6/7: 安装 Super-OS 配置"

log "复制 Super-OS 脚本..."
cp -r /root/super-os/* /mnt/root/super-os/
cp /root/super-os/iso/profile/packages.x86_64 /mnt/root/super-os/

# 安装用户级快捷命令
mkdir -p "/mnt/home/$USERNAME/.local/bin"
cat > "/mnt/home/$USERNAME/.local/bin/start-windows" << 'SW'
#!/bin/bash
sudo virsh start win11 2>/dev/null || bash ~/super-os/scripts/win11-vm.sh &
sleep 15
looking-glass-client &
SW
chmod +x "/mnt/home/$USERNAME/.local/bin/start-windows"

cat > "/mnt/home/$USERNAME/.local/bin/game-mode" << 'GM'
#!/bin/bash
gamemoderun bash ~/super-os/scripts/win11-vm.sh --game
GM
chmod +x "/mnt/home/$USERNAME/.local/bin/game-mode"

cat > "/mnt/home/$USERNAME/.local/bin/start-all" << 'SA'
#!/bin/bash
waydroid session start &
bash ~/super-os/scripts/win11-vm.sh &
sleep 20
looking-glass-client &
SA
chmod +x "/mnt/home/$USERNAME/.local/bin/start-all"

# 启用关键服务
log "启用系统服务..."
arch-chroot /mnt systemctl enable NetworkManager
arch-chroot /mnt systemctl enable sddm
arch-chroot /mnt systemctl enable libvirtd
arch-chroot /mnt systemctl enable bluetooth 2>/dev/null || true

# ─── 完成 ───
title "Step 7/7: 安装完成!"

log "Super-OS 已成功安装!"
echo ""
info "安装后的第一步:"
info "  1. 重启并拔掉 U 盘: reboot"
info "  2. 登录 KDE Plasma 桌面"
info "  3. 打开 Konsole, 运行:"
info "     sudo bash ~/super-os/scripts/setup-vfio.sh"
info "     sudo bash ~/super-os/scripts/setup-hugepages.sh"
info "     bash ~/super-os/scripts/setup-looking-glass.sh"
info "     bash ~/super-os/scripts/setup-waydroid.sh"
info "     bash ~/super-os/scripts/install-all.sh"
echo ""
warn "重要提醒:"
warn "  - 显示器线接主板 DP/HDMI (核显), 不接独显口"
warn "  - BIOS 中确保 iGPU Multi-Monitor 已开启"
echo ""
read -rp "按 Enter 重启或 Ctrl+C 退出..."
reboot
