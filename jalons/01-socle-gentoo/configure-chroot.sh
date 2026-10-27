#!/bin/bash
# ============================================================================
# GENTAura - JALON 1 (partie B) : A EXECUTER *DANS* LE CHROOT
# ----------------------------------------------------------------------------
# Usage : ./configure-chroot.sh <hostname> <user> <tz>   (ex: gentaura-vm alice Europe/Paris)
#         (copie ce script dans /mnt/gentoo/root/ avant d'entrer en chroot)
# ============================================================================
set -euo pipefail
HOSTNAME_="${1:?missing hostname}"; USERNAME="${2:?missing user}"; TZ="${3:?missing tz}"

echo ">>> [6/9] Configuration système de base"
echo "$HOSTNAME_" > /etc/conf.d/hostname 2>/dev/null || echo "$HOSTNAME_" > /etc/hostname
[ -f /etc/hostname ] || echo "$HOSTNAME_" > /etc/hostname
ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
echo "$TZ" > /etc/timezone
cat >> /etc/portage/make.conf <<'USETMP'
# (les USE globaux sont deja dans le profil aura de l'overlay gentaura)
USETMP

echo ">>> [7/9] Émergence du socle (systemd, réseau, audio, GPU)"
emerge --quiet --norequest-tree --with-bdeps=y \
  sys-kernel/gentoo-sources \
  sys-apps/systemd \
  net-misc/networkmanager \
  net-wireless/iwd \
  media-video/pipewire \
  media-libs/mesa \
  dev-libs/libinput \
  sys-fs/e2fsprogs \
  app-editors/nano \
  net-misc/dhcpcd \
  sys-boot/grub \
  app-crypt/gnupg \
  dev-build/binutils \
  dev-libs/nss \
  gnome-base/libgtop 2>/dev/null || \
emerge --quiet sys-kernel/gentoo-sources sys-apps/systemd net-misc/networkmanager \
  media-video/pipewire media-libs/mesa dev-libs/libinput sys-boot/grub

# Masque les services systemd inutiles pour la mini-distro (KPI RAM < 650 Mo)
for s in systemd-timesyncd; do systemctl mask "$s" 2>/dev/null || true; done
systemctl enable NetworkManager iwd 2>/dev/null || true
systemctl enable sshd 2>/dev/null || true

echo ">>> [8/9] Noyau : contrat GentAura + compilation"
cp /root/kernel.config /etc/kernel-config.d/gentaura.fragment 2>/dev/null || \
  mkdir -p /etc/kernel-config.d && cp /root/kernel.config /etc/kernel-config.d/gentaura.fragment
SRC=$(ls -d /usr/src/linux-* | tail -1)
cd "${SRC}/linux" 2>/dev/null || cd "$(dirname $SRC)/linux"
make defconfig
# Fusion stricte du contrat via merge_config.sh (scripts/bin/ ou scripts/kconfig/)
MC=$(find . -name merge_config.sh | head -1)
bash "$MC" --config kernel/configs/gentaura.fragment --temp-config .merge_config \
          -m /etc/kernel-config.d/gentaura.fragment
yes "" | make olddefconfig
# Verrouillage dur des options critiques (echoue si pas possible)
for c in CONFIG_DRM CONFIG_UDMABUF CONFIG_DMA_SHARED_BUFFER CONFIG_SYNC_FILE \
         CONFIG_VIRTUALIZATION CONFIG_KVM CONFIG_VHOST_VSOCK CONFIG_VIRTIO_GPU \
         CONFIG_CGROUPS CONFIG_MEMCG CONFIG_PSI CONFIG_USER_NS CONFIG_SECCOMP; do
  grep -q "^${c}=y\|^${c}=m" .config || { echo "!! ${c} absente du .config final"; exit 1; }
done
echo ">>> Contrat noyau verrouille OK — compilation..."
make -j"$(nproc)" && make install modules_install
cd /

echo ">>> [9/9] Utilisateur, mot de passe root, fstab, bootloader"
useradd -m -G wheel,video,audio,input,render,lp "$USERNAME" || true
passwd -l root >/dev/null 2>&1 || true
echo "!!! DEFINIS MAINTENANT LES MOTS DE PASSE : passwd ; passwd $USERNAME"
grep -q '^%wheel.*NOPASSWD' /etc/sudoers || echo '%wheel ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
cat > /etc/fstab <<'FSTAB'
/dev/nvme0n1p3  /     ext4  defaults,noatime,discard  0 1
/dev/nvme0n1p1  /boot vfat  defaults                  0 2
tmpfs           /run  tmpfs nodev,nosuid,size=10%     0 0
FSTAB
echo ">>> Adapte /etc/fstab a tes vrais UUID (blkid), puis :"
echo "    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GENTaura"
echo "    grub-mkconfig -o /boot/grub/grub.cfg"
echo ">>> TERMINE. exit, umount -R /mnt/gentoo, reboot."
