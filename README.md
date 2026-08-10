# Super-OS

> **Windows 11 VM + Android 全兼容 Linux 发行版**
>
> Intel Core Ultra 9 | Intel Arc 核显 + 独显 VFIO 直通 | KDE Plasma Wayland | Looking Glass 零延迟

```
   ┌─────────────────────────────────────────────────┐
   │              KDE Plasma (Wayland)                │
   │  ┌─────────┐  ┌──────────┐  ┌────────────────┐  │
   │  │  Linux  │  │ Windows  │  │    Android     │  │
   │  │  Apps   │  │  11 VM   │  │   (Waydroid)   │  │
   │  └─────────┘  └────┬─────┘  └───────┬────────┘  │
   │                    │                │            │
   │    Intel Arc 核显  │  VFIO 直通    │  Waydroid  │
   │    (Linux 宿主)    │  (独显→Win11) │  容器      │
   └────────────────────┴────────────────┴────────────┘
```

## 特性

- ✅ **完整 Windows 11** — KVM 虚拟机，100% Windows 兼容
- ✅ **AAA 游戏 98%+** — VFIO GPU 直通，独显原生驱动
- ✅ **零延迟显示** — Looking Glass IVSHMEM 共享内存 (< 1ms)
- ✅ **Android 应用** — Waydroid 容器，独立 Wayland 窗口
- ✅ **单系统** — Linux + Windows + Android 三合一

## 硬件要求

- **CPU**: Intel Core Ultra 9 (核显必须可用)
- **GPU**: Intel Arc 核显 (宿主) + 独立显卡 (VM 直通)
- **主板**: IOMMU (VT-d) + iGPU Multi-Monitor 支持
- **内存**: 32 GB+
- **存储**: 512 GB+ NVMe SSD

## 快速开始

```bash
# 1. 安装 Arch Linux (参考 install-guide.md)
# 2. 配置 VFIO GPU 直通
sudo bash scripts/setup-vfio.sh

# 3. 配置 HugePages
sudo bash scripts/setup-hugepages.sh

# 4. 创建 Windows 11 VM
bash scripts/win11-vm.sh --install

# 5. 安装 Looking Glass
bash scripts/setup-looking-glass.sh

# 6. 安装 Waydroid
bash scripts/setup-waydroid.sh

# 7. 一键集成
bash scripts/install-all.sh
```

## 日常使用

| 命令 | 说明 |
|------|------|
| `start-all` | 启动全部服务 |
| `start-windows` | 启动 Windows 11 + Looking Glass |
| `game-mode` | 全屏游戏 (evdev 直通 + 相对鼠标) |

## 快捷键

| 快捷键 | 功能 |
|------|------|
| `Meta+1` | Linux 桌面 |
| `Meta+2` | Windows 11 桌面 |
| `Meta+3` | Android 桌面 |
| `ScrollLock` | 释放/捕获 键鼠 (游戏模式) |

## 目录结构

```
super-os/
├── README.md                 # 项目说明
├── install-guide.md          # 详细安装指南
├── scripts/
│   ├── setup-vfio.sh         # VFIO GPU 直通配置
│   ├── setup-hugepages.sh    # 大页内存配置
│   ├── setup-looking-glass.sh # Looking Glass 编译
│   ├── setup-waydroid.sh     # Waydroid 安装
│   ├── win11-vm.sh           # Windows 11 VM 启动器
│   ├── single-gpu-vfio.sh    # 单卡切换脚本 (备选)
│   └── install-all.sh        # 一键集成
└── configs/
    ├── modprobe/             # VFIO 内核模块配置
    ├── sysctl/               # 系统优化参数
    ├── qemu/                 # libvirt XML 模板
    └── kde/                  # KDE 桌面集成
```
