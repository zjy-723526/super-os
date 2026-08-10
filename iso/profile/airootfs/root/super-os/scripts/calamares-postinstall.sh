#!/bin/bash
# Super-OS Calamares Post-Install Script
# 在目标系统的 chroot 中运行
# 配置中文环境、输入法、系统优化

set -euo pipefail

echo "=========================================="
echo " Super-OS Post-Install Setup (中文环境)"
echo "=========================================="

# ─── 获取安装的目标用户 ───
TARGET_USER=$(ls /home/ | head -1)
if [[ -z "$TARGET_USER" ]]; then
    echo "WARNING: No user found in /home, skipping user config"
    TARGET_USER=""
fi

# ─── 1. 配置中文 Locale ───
echo "[1/9] 配置中文语言环境..."

# 生成 locale
echo "zh_CN.UTF-8 UTF-8" > /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# 系统默认语言
cat > /etc/locale.conf << 'LOC'
LANG=zh_CN.UTF-8
LC_NUMERIC=zh_CN.UTF-8
LC_TIME=zh_CN.UTF-8
LC_MONETARY=zh_CN.UTF-8
LC_PAPER=zh_CN.UTF-8
LC_MEASUREMENT=zh_CN.UTF-8
LOC

# 设置时区为中国
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc

echo "  系统语言: zh_CN.UTF-8"
echo "  时区: Asia/Shanghai"

# ─── 2. 配置 pacman 中国镜像源 ───
echo "[2/9] 配置中国镜像源..."

if [[ -f /etc/pacman.d/mirrorlist ]]; then
    # 备份原文件
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak

    # 使用清华和中科大镜像 (优先级)
    cat > /etc/pacman.d/mirrorlist << 'MIRROR'
## Super-OS 中国镜像源
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch
Server = https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch
Server = https://mirrors.aliyun.com/archlinux/$repo/os/$arch
Server = https://mirrors.163.com/archlinux/$repo/os/$arch
Server = https://mirror.lzu.edu.cn/archlinux/$repo/os/$arch
Server = https://mirrors.sjtug.sjtu.edu.cn/archlinux/$repo/os/$arch
## 全球镜像 (备用)
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
MIRROR

    echo "  已配置清华/中科大/阿里云/163/兰州大学/上交镜像"
fi

# 添加archlinuxcn源 (中文社区包)
cat >> /etc/pacman.conf << 'CNREPO'

# Arch Linux CN 中文社区源
[archlinuxcn]
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/$arch
Server = https://mirrors.ustc.edu.cn/archlinuxcn/$arch
Server = https://mirrors.aliyun.com/archlinuxcn/$arch
CNREPO

# 导入 archlinuxcn key
pacman-key --init 2>/dev/null || true
pacman -Sy --noconfirm archlinuxcn-keyring 2>/dev/null || true
echo "  已添加 archlinuxcn 中文社区源"

# ─── 3. 配置内核参数 (IOMMU) ───
echo "[3/9] 配置内核启动参数..."

# 获取 root 分区 UUID
ROOT_UUID=$(findmnt -no UUID / 2>/dev/null || echo "")

if [[ -d /boot/loader ]]; then
    # systemd-boot
    cat > /boot/loader/loader.conf << 'LDR'
default super-os.conf
timeout 3
console-mode max
editor no
LDR

    cat > /boot/loader/entries/super-os.conf << BOOT
title   Super-OS
linux   /vmlinuz-linux-zen
initrd  /intel-ucode.img
initrd  /initramfs-linux-zen.img
options root=UUID=$ROOT_UUID rootflags=subvol=@ rw quiet intel_iommu=on iommu=pt locale=zh_CN.UTF-8
BOOT

    cat > /boot/loader/entries/super-os-fallback.conf << BOOTF
title   Super-OS (fallback)
linux   /vmlinuz-linux-zen
initrd  /intel-ucode.img
initrd  /initramfs-linux-zen-fallback.img
options root=UUID=$ROOT_UUID rootflags=subvol=@ rw intel_iommu=on iommu=pt
BOOTF
    echo "  systemd-boot 已配置 (含 IOMMU 参数)"
fi

# ─── 4. 启用系统服务 ───
echo "[4/9] 启用系统服务..."
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable libvirtd
systemctl enable bluetooth 2>/dev/null || true

# ─── 5. 配置 sudo ───
echo "[5/9] 配置用户权限..."
if [[ -n "$TARGET_USER" ]]; then
    echo "$TARGET_USER ALL=(ALL:ALL) ALL" > /etc/sudoers.d/99-superos
    chmod 440 /etc/sudoers.d/99-superos
    # 将用户加入必要组
    usermod -aG wheel,audio,video,storage,kvm,libvirt,input "$TARGET_USER"
fi

# ─── 6. 配置 SDDM 自动登录 ───
echo "[6/9] 配置自动登录..."
if [[ -n "$TARGET_USER" ]]; then
    mkdir -p /etc/sddm.conf.d
    cat > /etc/sddm.conf.d/autologin.conf << SDDM
[Autologin]
User=$TARGET_USER
Session=plasma.desktop

[Theme]
Current=breeze
SDDM
    echo "  SDDM 自动登录: $TARGET_USER"
fi

# ─── 7. 安装 Super-OS 脚本到用户目录 ───
echo "[7/9] 安装 Super-OS 脚本..."
if [[ -n "$TARGET_USER" ]]; then
    # 复制脚本
    mkdir -p "/home/$TARGET_USER/super-os"
    if [[ -d /root/super-os ]]; then
        cp -r /root/super-os/* "/home/$TARGET_USER/super-os/"
    fi

    # 快捷命令
    mkdir -p "/home/$TARGET_USER/.local/bin"

    cat > "/home/$TARGET_USER/.local/bin/start-windows" << 'SW'
#!/bin/bash
echo "启动 Windows 11 VM..."
bash ~/super-os/scripts/win11-vm.sh &
sleep 20
looking-glass-client &
echo "Windows 11 已启动, 在 Looking Glass 窗口中查看"
SW
    chmod +x "/home/$TARGET_USER/.local/bin/start-windows"

    cat > "/home/$TARGET_USER/.local/bin/game-mode" << 'GM'
#!/bin/bash
echo "进入游戏模式 (ScrollLock 释放键盘回 Linux)..."
gamemoderun bash ~/super-os/scripts/win11-vm.sh --game
GM
    chmod +x "/home/$TARGET_USER/.local/bin/game-mode"

    cat > "/home/$TARGET_USER/.local/bin/start-all" << 'SA'
#!/bin/bash
echo "=== Super-OS 启动中 ==="
echo "[1/3] Waydroid Android 容器..."
waydroid session start &
sleep 3
echo "[2/3] Windows 11 虚拟机..."
bash ~/super-os/scripts/win11-vm.sh &
sleep 25
echo "[3/3] Looking Glass 零延迟显示..."
looking-glass-client &
echo ""
echo "Super-OS 就绪!"
echo "  Meta+1 = Linux 桌面"
echo "  Meta+2 = Windows 11"
echo "  Meta+3 = Android"
SA
    chmod +x "/home/$TARGET_USER/.local/bin/start-all"

    # 桌面快捷方式
    mkdir -p "/home/$TARGET_USER/Desktop"

    cat > "/home/$TARGET_USER/Desktop/vfio-gpu-setup.desktop" << 'DSK1'
[Desktop Entry]
Name=配置 GPU 直通
Name[zh_CN]=配置 GPU 直通
Comment=检测独显并配置 VFIO 直通给 Windows VM
Comment[zh_CN]=检测独显并配置 VFIO 直通给 Windows VM
Exec=konsole -e bash -c "sudo bash ~/super-os/scripts/setup-vfio.sh; read -p '按 Enter 关闭...'"
Icon=preferences-system
Terminal=false
Type=Application
DSK1

    cat > "/home/$TARGET_USER/Desktop/full-setup.desktop" << 'DSK2'
[Desktop Entry]
Name=完整初始设置
Name[zh_CN]=完整初始设置
Comment=依次配置: GPU直通 → 大页内存 → Looking Glass → Waydroid → 桌面集成
Comment[zh_CN]=依次配置: GPU直通 → 大页内存 → Looking Glass → Waydroid → 桌面集成
Exec=konsole -e bash -c "echo '===== Super-OS 完整设置 ====='; echo ''; echo '1/5: VFIO GPU 直通...'; sudo bash ~/super-os/scripts/setup-vfio.sh; echo ''; echo '2/5: 大页内存...'; sudo bash ~/super-os/scripts/setup-hugepages.sh; echo ''; echo '3/5: Looking Glass...'; bash ~/super-os/scripts/setup-looking-glass.sh; echo ''; echo '4/5: Waydroid...'; bash ~/super-os/scripts/setup-waydroid.sh; echo ''; echo '5/5: 系统集成...'; bash ~/super-os/scripts/install-all.sh; echo ''; echo '===== 设置完成! ====='; read -p '按 Enter 关闭...'"
Icon=system-run
Terminal=false
Type=Application
DSK2

    # 设置所有者
    chown -R "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/super-os"
    chown -R "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.local"
    chown "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/Desktop"/*.desktop 2>/dev/null || true
fi

# ─── 8. 配置中文输入法 (fcitx5) ───
echo "[8/9] 配置中文输入法..."

if [[ -n "$TARGET_USER" ]]; then
    # 创建 fcitx5 环境变量
    mkdir -p "/home/$TARGET_USER/.config/environment.d"
    cat > "/home/$TARGET_USER/.config/environment.d/fcitx5.conf" << 'FCENV'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=ibus
FCENV

    # 创建 fcitx5 配置文件
    mkdir -p "/home/$TARGET_USER/.config/fcitx5"
    cat > "/home/$TARGET_USER/.config/fcitx5/config" << 'FCCFG'
[Hotkey]
TriggerKey=CTRL_SPACE
EnumerateForwardKey=CTRL_SHIFT
SwitchKey=Disabled

[Behavior]
ActiveByDefault=True
ShowInputMethodInformation=True
ShowInputMethodInformationWhenFocusIn=True
PreeditEnabledByDefault=True

[Addon]
Pinyin=fcitx5-chinese-addons

[InputMethod]
Groups=["Pinyin"]
GroupOrder=0:Pinyin
FCCFG

    cat > "/home/$TARGET_USER/.config/fcitx5/profile" << 'FCPROFILE'
[Groups/0]
Name=默认
Default Layout=us
DefaultIM=pinyin

[Groups/0/Items/0]
Name=pinyin
Layout=

[GroupOrder]
0=默认
FCPROFILE

    # fcitx5 自动启动
    mkdir -p "/home/$TARGET_USER/.config/autostart"
    cat > "/home/$TARGET_USER/.config/autostart/fcitx5.desktop" << 'FCAUTO'
[Desktop Entry]
Name=Fcitx 5
Comment=中文输入法
Exec=fcitx5
Icon=fcitx
Terminal=false
Type=Application
Categories=Utility;
X-KDE-autostart-phase=1
FCAUTO

    # 设置所有者
    chown -R "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.config"

    echo "  fcitx5 已配置: Ctrl+Space 切换中英文"
fi

# ─── 9. 系统优化 + 欢迎消息 ───
echo "[9/9] 应用系统优化..."

cat > /etc/sysctl.d/99-superos.conf << 'SYS'
# Super-OS Gaming Optimization
vm.swappiness=1
vm.vfs_cache_pressure=50
kernel.sched_autogroup_enabled=0
fs.file-max=2097152
vm.max_map_count=2147483642
SYS

# 中文欢迎消息
cat > /etc/motd << 'MOTD'
╔══════════════════════════════════════════════════════════════╗
║            欢迎使用 Super-OS!                               ║
║                                                            ║
║  桌面快捷方式:                                             ║
║    ┌──────────────────────────────────────────────┐        ║
║    │  🖥️  配置 GPU 直通    — 独显隔离给 Windows     │        ║
║    │  🚀  完整初始设置     — 一键跑完所有配置       │        ║
║    └──────────────────────────────────────────────┘        ║
║                                                            ║
║  终端命令:                                                 ║
║    start-all        启动所有服务 (Win11 + Android)         ║
║    start-windows    启动 Windows 11 + Looking Glass       ║
║    game-mode        AAA 游戏全屏模式                       ║
║                                                            ║
║  快捷键:                                                   ║
║    Ctrl+Space       切换中英文输入                          ║
║    Meta+1/2/3       切换虚拟桌面 (Linux/Win11/Android)     ║
║    ScrollLock        释放键盘鼠标 (游戏模式下)              ║
║                                                            ║
╚══════════════════════════════════════════════════════════════╝
MOTD

echo ""
echo "=========================================="
echo " Super-OS 安装完成! (中文环境)"
echo "=========================================="
echo ""
echo "  系统语言: 简体中文 (zh_CN.UTF-8)"
echo "  时区:     Asia/Shanghai"
echo "  输入法:   Fcitx5 拼音 (Ctrl+Space)"
echo "  镜像源:   清华/中科大/阿里云"
echo ""
echo "  重启后登录, 点击桌面快捷方式开始配置!"
echo ""
