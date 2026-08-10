#!/usr/bin/env bash
# Super-OS archiso profile definition
# Build: mkarchiso -v -o /output ./profile

# Architecture
arch="x86_64"

# ISO metadata
iso_name="super-os"
iso_label="SUPER_OS_$(date +%Y%m)"
iso_publisher="Super-OS Project"
iso_application="Super-OS Live/Installation Media"
iso_version="$(date +%Y.%m.%d)"

# Boot modes
bootmodes=("bios.syslinux.mbr" "bios.syslinux.eltorito" "uefi-x64.systemd-boot.esp" "uefi-x64.systemd-boot.eltorito")

# Build mode
buildmode="iso"

# File permissions
# All files in airootfs get root:root by default

# Packages to install in live environment
# These are defined in packages.x86_64

# Custom pacman.conf
pacman_conf="pacman.conf"

# Custom airootfs
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')

# Bootstrap tarball compression
bootstrap_tarball_compression=("zstd" "-c" "-T0" "-19" "-")

# File system permission options
file_permissions=(
  # Allow passwordless sudo for live user
  ["/etc/sudoers.d/live"]="0:0:440"
  # Scripts executable
  ["/root/super-os/scripts/"]="0:0:755"
  ["/root/super-os/scripts/setup-vfio.sh"]="0:0:755"
  ["/root/super-os/scripts/setup-hugepages.sh"]="0:0:755"
  ["/root/super-os/scripts/setup-looking-glass.sh"]="0:0:755"
  ["/root/super-os/scripts/setup-waydroid.sh"]="0:0:755"
  ["/root/super-os/scripts/win11-vm.sh"]="0:0:755"
  ["/root/super-os/scripts/single-gpu-vfio.sh"]="0:0:755"
  ["/root/super-os/scripts/install-all.sh"]="0:0:755"
  ["/root/super-os/scripts/install-to-disk.sh"]="0:0:755"
  # KDE configs
  ["/root/super-os/configs/kde/virtual-desktops.sh"]="0:0:755"
)
