#!/usr/bin/env bash
# =============================================================================
# Jalon 5 - Construction de l'image racine invitee (TDD roadmap 6.5 :
# "image racine invitee minimale (SquashFS)").
# Pipeline : stage3 Gentoo -> chroot minimalise -> injection sommelier/xwl +
# init systemd VM -> ext4 image bootee par crosvm (--rw, writable layer) OU
# squashfs erofs read-only + overlay. Kernel invite en bzImage EXTERNE.
# Idempotent : re-executable, reconstruction complete a chaque run.
# =============================================================================
set -euo pipefail
OUT="${GENTAURA_STAGE5_OUT:-$HOME/.cache/gentaura/stage5}"
VMDIR="${GENTAURA_VM_DIR:-/var/lib/gentaura/vm}"   # sudo requis si systeme
WORK="$OUT/image-work"
STAGE3_URL="https://gentoo.org/downloads/mirrors/"   # choisir un miroir ci-dessous
MIRROR="${GENTOO_MIRROR:-https://bouncer.gentoo.org/fetch/root/all/releases}"
REL="$(curl -sL "$MIRROR/" | grep -oE 'amd64-autobuild-[0-9]+' | head -1 || echo amd64-autobuild-bootstrap-20261025T144852Z)"
IMG="$WORK/rootfs.img"
SIZE_MB=2047

log(){ printf '\n\033[1;36m[stage5-image]\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------- 1. stage3
if [[ ! -f "$WORK/stage3.tar.xz" ]]; then
  mkdir -p "$WORK"
  log "telechargement stage3 ($REL)..."
  curl -fL -o "$WORK/stage3.tar.xz" "$MIRROR/$REL/stage3-amd64-musl-merged-usr-$REL.tar.xz" \
  || curl -fL -o "$WORK/stage3.tar.xz" "$MIRROR/$REL/stage3-amd64-openrc-$REL.tar.xz" \
  || { echo "ERREUR : miroir/relance — voir README (variable GENTOO_MIRROR)"; exit 1; }
fi
rm -rf "$WORK/rootfs"; mkdir -p "$WORK/rootfs"
log "extraction stage3 -> rootfs..."
tar xpf "$WORK/stage3.tar.xz" -C "$WORK/rootfs"

# ------------------------------------------------------- 2. surcouche overlay
log "application de la surcouche guest-overlay/..."
cp -a ../guest-overlay/etc/portage/. "$WORK/rootfs/etc/portage/"
mkdir -p "$WORK/rootfs/etc/portage/repos.conf"
cat > "$WORK/rootfs/etc/portage/repos.conf/gentoo.conf" <<CONF
[DEFAULT]
main-repo = gentoo
[gentoo]
location = /var/db/repos/gentoo
sync-type = git
sync-uri = https://github.com/gentoo-mirror/gentoo.git
auto-sync = no
CONF

# --------------------------------------------- 3. paquets minimaux du pipeline
log "emerge des paquets invites (via qemu-user ou chroot natif si arch match)..."
cat > "$WORK/emerge-list.txt" <<PKGS
dev-libs/wayland
media-libs/mesa
app-misc/foot
x11-apps/xterm
sys-apps/systemd
net-misc/openssh
PKGS
if command -v proot >/dev/null && [[ "$(uname -m)" == x86_64 ]]; then
  # Montage bind des distfiles + emerge binaire prioritaire (BINHOST!)
  mount --bind /var/cache/distfiles "$WORK/rootfs/var/cache/distfiles" 2>/dev/null || true
  proot -R "$WORK/rootfs" /bin/sh -c "emerge --quiet --usepkg --ask=n $(tr '\n' ' ' < "$WORK/emerge-list.txt")" || true
else
  log "NOTE : build cross-arch — lancer cette etape DANS le chroot BINHOST x86_64"
fi

# ------------------------------------------- 4. injection sommelier + service
log "injection de sommelier/xwl depuis sysroot-vm..."
[[ -d "$OUT/sysroot-vm" ]] && cp -a "$OUT/sysroot-vm/usr/bin/sommelier" "$OUT/sysroot-vm/usr/bin/xwl" "$WORK/rootfs/usr/bin/" 2>/dev/null || log "WARN: sommelier absent (lancer build-sommelier.sh avant image)"
mkdir -p "$WORK/rootfs/etc/systemd/system"
cat > "$WORK/rootfs/etc/systemd/system/sommelier.service" <<UNIT
[Unit]
Description=Sommelier proxy Wayland/X11 pour projection Zero-Copy vers Exo (hote)
After=systemd-udevd.service
[Service]
ExecStart=/usr/bin/sommelier --virtio-gpu --xwl --wayland-display=wayland-0
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
ln -sf ../sommelier.service "$WORK/rootfs/etc/systemd/system/multi-user.target.wants/sommelier.service"
printf 'root\n' > "$WORK/rootfs/etc/hostname"
echo -e "root::\n" | chroot "$WORK/rootfs" /usr/sbin/chpasswd 2>/dev/null || log "root passwd vide (dev only)"

# ------------------------------------------------- 5. kernel invite + image fs
log "kernel invite : copie du bzImage hote (modules virtio requis au menu)..."
mkdir -p "$VMDIR" 2>/dev/null || sudo mkdir -p "$VMDIR"
for k in /boot/bzImage /boot/vmlinuz-*; do [[ -e $k ]] && sudo cp "$k" "$VMDIR/vmlinuz" && break; done
log "creation image ext4 ${SIZE_MB} Mo + rsync rootfs..."
dd if=/dev/zero of="$IMG" bs=1M count=$SIZE_MB status=none
mkfs.ext4 -q -F -d "$WORK/rootfs" "$IMG" 2>/dev/null || {
  mdir=$(sudo mktemp -d); sudo mount -o loop "$IMG" "$mdir"
  sudo rsync -aHAX "$WORK/rootfs/" "$mdir/"; sudo umount "$mdir"; rmdir "$mdir"
}
if command -v mkfs.erofs >/dev/null; then
  log "variante EROFS read-only (COULD HAVE atomic updates)..."
  mkfs.erofs -z lz4 "$WORK/rootfs.erofs" "$WORK/rootfs" || true
fi
sudo cp "$IMG" "$VMDIR/rootfs.img" 2>/dev/null || cp "$IMG" "$VMDIR/rootfs.img"
log "OK -> $VMDIR/{rootfs.img,vmlinuz}"
