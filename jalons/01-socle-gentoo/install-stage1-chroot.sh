#!/bin/bash
# ============================================================================
# GENTAura - JALON 1 : Installation du socle Gentoo (systemd) en stage3 chroot
# ----------------------------------------------------------------------------
# Hypothèse : tu as déjà booté un LiveCD (SystemRescue / Install Gentoo),
#             partitionné, formaté et monté :
#   /mnt/gentoo            -> racine (ext4/btrfs)
#   /mnt/gentoo/boot       -> partition EFI (FAT32, ESP)  [GPT requis]
# Usage (depuis le LiveCD, réseau actif) :
#   ./install-stage1-chroot.sh <MIRROR_GENTOO> <HOSTNAME> <USER> <TZ>
# Exemple :
#   ./install-stage1-chroot.sh https://bouncer.gentoo.org/fetch/root/all \
#        gentaura-vm alice Europe/Paris
# Ce script est idempotent-ish : il s'arrête sur la première erreur (set -e).
# ============================================================================
set -euo pipefail

MIRROR="${1:?Usage: $0 <mirror> <hostname> <user> <tz>}"
HOSTNAME_="${2:?missing hostname}"
USERNAME="${3:?missing username}"
TZ="${4:?missing timezone}"
ROOT=/mnt/gentoo

echo ">>> [1/9] Téléchargement du stage3 (systemd, amd64, multilib)"
mkdir -p "$ROOT" && cd "$ROOT"
STAGE=$(curl -sL "$MIRROR/snapshots/" | grep -oP 'stage3-amd64-systemd-[0-9]+\.tar\.xz' | head -1)
[ -n "$STAGE" ] || { echo "!! stage3 systemd introuvable"; exit 1; }
wget -q --show-progress "$MIRROR/releases/amd64/autobuilds/current-stage3-amd64-systemd/$STAGE"
tar xpvf "$STAGE" --xattrs-include='*.*' --numeric-owner
rm -f "$STAGE"

echo ">>> [2/9] make.conf optimisé (march=native + BINHOST GentAura)"
cat > "$ROOT/etc/portage/make.conf" <<CONF
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
LDFLAGS="\${COMMON_FLAGS}"
CPU_FLAGS_X86="aes avx avx2 f16c fma3 mmx mmxext pclmul popcnt rdrand sse sse2 sse3 sse4_1 sse4_2 ssse3"
MAKEOPTS="-j\$(nproc)"
USE="systemd wayland ozone-drm pipewire -X -bluetooth-nextgui alsa dbus udev kms egl gles2 vulkan"
INPUT_DEVICES="libinput"
VIDEO_CARDS="amdgpu intel nvidia"   # ajuste au GPU reel de ta VM/cible
PORTAGE_BINHOST="https://binhost.gentaura.local/Packages"
GRUB_PLATFORMS=""
CONF

echo ">>> [3/9] Overlay GentAura + profil aura"
mkdir -p "$ROOT/etc/portage/repos.conf" "$ROOT/var/db/repos"
cat > "$ROOT/etc/portage/repos.conf/gentaura.conf" <<'REPO'
[gentaura]
location = /var/db/repos/gentaura
sync-type = git
sync-uri = file:///opt/gentaura-os
auto-sync = yes
REPO
# Depose l'overlay depuis ce depot (adapte le chemin si besoin)
git clone --local /workspace/gentaura-os "$ROOT/var/db/repos/gentaura" 2>/dev/null || true
cat > "$ROOT/etc/portage/make.profile" <<'PROF'
../../../var/db/repos/gentaura/profiles/default/linux/amd64/23.0/aura
PROF

echo ">>> [4/9] Portage baseline + copie DNS"
emerge-webrsync -q 2>/dev/null || emerge --sync -q
ln -sf /etc/portage/make.profile ../../../usr/share/portage/config/make.profile.default 2>/dev/null || true
cp -L /etc/resolv.conf "$ROOT/etc/"

echo ">>> [5/9] Montage pseudo-filesystems + enter chroot"
mount -t proc     proc     "$ROOT/proc"
mount --rbind     /sys     "$ROOT/sys"
mount --rbind     /dev     "$ROOT/dev"
printf '\nenter_chroot() {\n  mount -a 2>/dev/null\n  PS1="[gentaura-chroot] # " exec chroot %s /bin/bash -l\n}\n' "$ROOT" >> ~/.bashrc
source ~/.bashrc
echo ">>> Monte. Lance maintenant :  enter_chroot"
