# Super-OS 安装指南

> **Intel Core Ultra 9 + 独显 | Windows 11 VM + Android | KDE Plasma Wayland**

## 概述

本指南将引导你完成一个自定义 Arch Linux 系统的安装，该系统通过 KVM/QEMU 运行完整 Windows 11 虚拟机，使用 VFIO GPU 直通获得 AAA 游戏性能，通过 Looking Glass 将 Windows 桌面以零延迟显示在 KDE 桌面上，同时通过 Waydroid 运行 Android 应用。

## 硬件要求

- CPU: Intel Core Ultra 9 (已确认)
- 主板: IOMMU 支持 (VT-d)，IGD Multi-Monitor 选项
- GPU: Intel Arc 核显 + 独立显卡 (NVIDIA/AMD)
- RAM: 32 GB 以上
- 存储: 512 GB+ NVMe SSD

## 安装步骤

### 第一步：准备 Arch Linux 安装介质

1. 下载 [Arch Linux ISO](https://archlinux.org/download/)
2. 使用 Rufus 或 Ventoy 制作启动 U 盘
3. **重要**：进入 BIOS，确保：
   - Intel VT-d (IOMMU) → **Enabled**
   - IGD Multi-Monitor / iGPU Always Enable → **Enabled**
   - Secure Boot → **Disabled** (方便后续操作)
   - Fast Boot → **Disabled**

### 第二步：安装基础系统

```bash
# 确认启动模式为 UEFI
ls /sys/firmware/efi/efivars

# 连接网络
iwctl

# 分区 (示例: NVMe SSD /dev/nvme0n1)
parted /dev/nvme0n1 mklabel gpt
parted /dev/nvme0n1 mkpart primary fat32 1MiB 513MiB
parted /dev/nvme0n1 set 1 esp on
parted /dev/nvme0n1 mkpart primary btrfs 513MiB 100%

# 格式化
mkfs.fat -F32 /dev/nvme0n1p1
mkfs.btrfs -f /dev/nvme0n1p2

# 创建 Btrfs 子卷
mount /dev/nvme0n1p2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
umount /mnt

# 挂载
mount -o compress=zstd,subvol=@ /dev/nvme0n1p2 /mnt
mkdir -p /mnt/{boot,home,.snapshots}
mount /dev/nvme0n1p1 /mnt/boot
mount -o compress=zstd,subvol=@home /dev/nvme0n1p2 /mnt/home
mount -o compress=zstd,subvol=@snapshots /dev/nvme0n1p2 /mnt/.snapshots

# 安装基础包
pacstrap /mnt base linux-zen linux-zen-headers linux-firmware base-devel
pacstrap /mnt btrfs-progs intel-ucode
pacstrap /mnt networkmanager vim git curl wget
pacstrap /mnt efibootmgr

# 生成 fstab
genfstab -U /mnt >> /mnt/etc/fstab

# chroot
arch-chroot /mnt

# 设置时区
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc

# 设置 locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# 主机名
echo "super-os" > /etc/hostname

# 设置 root 密码
passwd

# 安装 systemd-boot
bootctl --path=/boot install

# 创建引导条目
cat > /boot/loader/entries/arch.conf << 'BOOTEOF'
title   Super-OS
linux   /vmlinuz-linux-zen
initrd  /intel-ucode.img
initrd  /initramfs-linux-zen.img
options root=UUID=REPLACE_WITH_ROOT_UUID rootflags=subvol=@ rw quiet intel_iommu=on iommu=pt
BOOTEOF

# 替换 UUID
ROOT_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2)
sed -i "s/REPLACE_WITH_ROOT_UUID/$ROOT_UUID/" /boot/loader/entries/arch.conf

# 创建 loader.conf
cat > /boot/loader/loader.conf << EOF
default arch.conf
timeout 3
console-mode max
editor no
EOF

# 退出 chroot, 重启
exit
reboot
```

### 第三步：安装 GPU 驱动和 KDE

```bash
# 确保网络正常
sudo systemctl enable --now NetworkManager

# 创建用户
useradd -m -G wheel,users,audio,video,storage,kvm,libvirt -s /bin/bash zjy
passwd zjy
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# Intel Arc 核显驱动
sudo pacman -S mesa vulkan-intel intel-media-driver vulkan-icd-loader libva-utils

# KDE Plasma 6 Wayland
sudo pacman -S plasma-meta plasma-wayland-session konsole dolphin
sudo pacman -S kde-applications-meta  # 可选，完整应用套件

# 音频
sudo pacman -S pipewire pipewire-pulse wireplumber pipewire-alsa

# 基础工具
sudo pacman -S firefox kitty neovim htop btop fastfetch

# 启用 SDDM
sudo systemctl enable sddm
sudo systemctl enable NetworkManager

reboot
```

### 第四步：配置 VFIO GPU 直通

**本步骤将独显从 Linux 宿主隔离，准备直通给 Windows VM。**

```bash
# 1. 查看独显 PCI ID 和 IOMMU 组
lspci -nn | grep -i "vga\|3d\|display"
# 找到独显条目，记录 VEN_ID:DEV_ID (例如 NVIDIA 是 10de:xxxx)

# 查看 IOMMU 分组
for d in /sys/kernel/iommu_groups/*/devices/*; do
  n=${d#*/iommu_groups/*}; n=${n%%/*}
  printf "IOMMU Group %s - %s\n" "$n" "$(lspci -nns "${d##*/}")"
done

# 2. 运行 VFIO 配置脚本
sudo bash /path/to/super-os/scripts/setup-vfio.sh
```

### 第五步：配置大页内存

```bash
sudo bash /path/to/super-os/scripts/setup-hugepages.sh
```

### 第六步：创建 Windows 11 VM

```bash
# 安装虚拟化组件
sudo pacman -S qemu-full libvirt virt-manager edk2-ovmf swtpm
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER

# 复制 VM 启动脚本
cp /path/to/super-os/scripts/win11-vm.sh ~/bin/
chmod +x ~/bin/win11-vm.sh

# 准备 Windows 11 ISO
# 下载 Windows 11 ISO 放到 /var/lib/libvirt/images/

# 创建虚拟磁盘
qemu-img create -f qcow2 /var/lib/libvirt/images/win11.qcow2 256G

# 首次启动 (安装 Windows)
~/bin/win11-vm.sh --install
```

### 第七步：Windows 11 初始化

在 VM 内完成以下操作：

1. 安装 Windows 11
2. 安装 VirtIO 驱动 (virtio-win ISO)
3. 安装独显官方驱动 (NVIDIA Game Ready / AMD Adrenalin)
4. 安装 Looking Glass Host
5. 安装 SPICE Guest Tools
6. 关闭 Windows Game Bar / DVR

### 第八步：安装 Looking Glass Client

```bash
bash /path/to/super-os/scripts/setup-looking-glass.sh
```

### 第九步：安装 Waydroid

```bash
bash /path/to/super-os/scripts/setup-waydroid.sh
```

### 第十步：系统集成

```bash
# 安装所有集成脚本
bash /path/to/super-os/scripts/install-all.sh
```

## 日常使用

```bash
# 启动所有服务
start-all

# 仅启动 Windows
start-windows

# 游戏模式 (全屏)
game-mode

# 切换 Windows 应用
switch-to-windows
```
