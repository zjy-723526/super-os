#!/bin/bash
# Super-OS KDE 虚拟桌面布局配置
# 桌面 1: Linux 原生应用
# 桌面 2: Windows 11 (Looking Glass 全屏)
# 桌面 3: Android 应用 (Waydroid)

# ─── 通过 kwriteconfig5 配置 KDE ───

# 设置 3 个虚拟桌面
kwriteconfig5 --file kwinrc \
    --group Desktops \
    --key Number 3 \
    --key Rows 1

# 桌面名称
kwriteconfig5 --file kwinrc \
    --group Desktops \
    --key Name_1 "Linux"
kwriteconfig5 --file kwinrc \
    --group Desktops \
    --key Name_2 "Windows 11"
kwriteconfig5 --file kwinrc \
    --group Desktops \
    --key Name_3 "Android"

# 快捷键: Meta+1/2/3 切换桌面
kwriteconfig5 --file kglobalshortcutsrc \
    --group kwin \
    --key "Switch to Desktop 1" "Meta+1,none,切换桌面 1"
kwriteconfig5 --file kglobalshortcutsrc \
    --group kwin \
    --key "Switch to Desktop 2" "Meta+2,none,切换桌面 2"
kwriteconfig5 --file kglobalshortcutsrc \
    --group kwin \
    --key "Switch to Desktop 3" "Meta+3,none,切换桌面 3"

# 应用设置
qdbus org.kde.KWin /KWin reconfigure

echo "KDE 虚拟桌面布局配置完成!"
echo "  桌面 1 (Meta+1): Linux 原生"
echo "  桌面 2 (Meta+2): Windows 11"
echo "  桌面 3 (Meta+3): Android"
