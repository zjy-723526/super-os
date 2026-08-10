#!/bin/bash
# Super-OS Live Environment Bootstrap (中文环境)

# ─── 设置 live 用户密码 ───
echo "root:superos" | chpasswd

# ─── 创建 liveuser ───
if ! id "liveuser" &>/dev/null; then
    useradd -m -G wheel,audio,video,storage,kvm,libvirt,input -s /bin/bash liveuser
    echo "liveuser:liveuser" | chpasswd
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/live
fi

# ─── 配置 locale ───
echo "zh_CN.UTF-8 UTF-8" > /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=zh_CN.UTF-8" > /etc/locale.conf

# ─── 设置键盘布局 ───
loadkeys us 2>/dev/null || true
localectl set-keymap us 2>/dev/null || true

# ─── 启动 NetworkManager ───
systemctl enable --now NetworkManager

# ─── 中文欢迎消息 ───
cat > /etc/motd << 'MOTD'
╔══════════════════════════════════════════════════════════════╗
║              Super-OS Live 环境                             ║
║       Windows 11 VM + Android 全兼容 Linux                  ║
║                                                            ║
║  图形安装器已自动启动。如果没有弹出, 运行:                 ║
║    calamares                                               ║
║                                                            ║
║  命令行安装:                                               ║
║    sudo install-super-os                                   ║
║                                                            ║
║  测试硬件:                                                 ║
║    vfio-check          检查 GPU IOMMU 分组                 ║
║    ls ~/super-os/scripts/  查看所有脚本                    ║
║                                                            ║
║  用户名: liveuser    密码: liveuser                        ║
║  root 密码: superos                                        ║
╚══════════════════════════════════════════════════════════════╝
MOTD

cat /etc/motd

# ─── 创建快捷命令 ───
ln -sf /root/super-os/scripts/install-to-disk.sh /usr/local/bin/install-super-os 2>/dev/null || true
ln -sf /root/super-os/scripts/setup-vfio.sh /usr/local/bin/vfio-check-live 2>/dev/null || true
ln -sf /usr/bin/calamares /usr/local/bin/installer 2>/dev/null || true
