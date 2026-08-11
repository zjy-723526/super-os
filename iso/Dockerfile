FROM archlinux:latest

# ─── China mirrors for faster package downloads ───
RUN echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist \
    && pacman -Syu --noconfirm

# ─── Build tools ───
RUN pacman -S --noconfirm --needed archiso git base-devel sudo

# ─── Build calamares from AUR ───
RUN useradd -m builder \
    && echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers \
    && cd /tmp \
    && git clone https://aur.archlinux.org/calamares.git \
    && chown -R builder:builder calamares \
    && cd calamares \
    && sudo -u builder makepkg -s --noconfirm --needed --nocheck \
    && mkdir -p /tmp/superos-repo \
    && cp *.pkg.tar.zst /tmp/superos-repo/ \
    && cd /tmp/superos-repo \
    && repo-add superos-repo.db.tar.gz *.pkg.tar.zst \
    && rm -rf /tmp/calamares

# ─── Cleanup ───
RUN pacman -Scc --noconfirm 2>/dev/null || true
