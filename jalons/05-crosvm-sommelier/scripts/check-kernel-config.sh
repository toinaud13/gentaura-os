#!/usr/bin/env bash
# =============================================================================
# Jalon 5 - Etape "check" : pre-vol noyau Phase 2 + droits hyperviseur + outils
# Idempotent, lecture seule (sauf --fix qui cree un modprobe.d persistant).
# =============================================================================
set -uo pipefail
PASS=0; FAIL=0
ok(){ printf '  \033[1;32m✔\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
ko(){ printf '  \033[1;31m✘\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
warn(){ printf '  \033[1;33m⚠\033[0m %s\n' "$*"; }

echo "== A. Contrat noyau Phase 2 =="
KCFG=""
for c in "/boot/config-$(uname -r)" "/lib/modules/$(uname -r)/config" "/proc/config.gz"; do
  [[ -e "$c" ]] && KCFG="$c" && break
done
read_cfg() { # $1 option -> valeur ou vide
  [[ -z "$KCFG" ]] && return 1
  if [[ "$KCFG" == *.gz ]]; then zcat "$KCFG"; else cat "$KCFG"; fi | grep -E "^$1=" | head -1 | cut -d= -f2
}
declare -A NEED=( [CONFIG_KVM]=y [CONFIG_VHOST_VSOCK]=m [CONFIG_UDMABUF]=y [CONFIG_SYNC_FILE]=y [CONFIG_DMA_SHARED_BUFFER]=y )
if [[ -n "$KCFG" ]]; then
  for opt in "${!NEED[@]}"; do
    v="$(read_cfg "$opt" || true)"
    exp="${NEED[$opt]}"
    if [[ "$v" == "$exp" || ( "$exp" == m && "$v" == y ) ]]; then ok "$opt=$v"; else ko "$opt='${v:-non define}' (attendu ${exp})"; fi
  done
  vi="$(read_cfg CONFIG_VIRTIO_GPU || true)"; kvmx="$(read_cfg CONFIG_KVM_INTEL || true)"; kvma="$(read_cfg CONFIG_KVM_AMD || true)"
  [[ -n "$vi" ]] && ok "CONFIG_VIRTIO_GPU=$vi" || ko "CONFIG_VIRTIO_GPU absent"
  [[ -n "$kvmx$kvma" || -n "$kvmx$kvma" ]] && ok "pilote KVM CPU present (intel=$kvmx amd=$kvma)" || ko "ni KVM_INTEL ni KVM_AMD"
else
  warn "config noyau introuvable — repli sur lsmod"
fi

echo "== B. Modules charges / chargeables =="
for m in kvm vhost_vsock virtio_net virtio_gpu; do
  if lsmod | grep -q "^${m} "; then ok "module charge : $m"
  elif modinfo "$m" >/dev/null 2>&1; then warn "module present mais non charge : $m (modprobe $m)"
  else ko "module introuvable : $m"; fi
done

echo "== C. Peripheriques & droits =="
[[ -e /dev/kvm ]] && ok "/dev/kvm present" || ko "/dev/kvm absent (Virtualization BIOS ?)"
[[ -r /dev/kvm && -w /dev/kvm ]] && ok "/dev/kvm accessible en rw pour $(id -un)" || ko "/dev/kvm non rw — groupadd/usermod kvm + regle udev systemd/"
[[ -e /dev/vhost-vsock ]] && ok "/dev/vhost-vsock present" || warn "/dev/vhost-vsock absent (modprobe vhost-vsock + udev rule)"
cpuinfo=$(grep -oE 'vmx|svm' /proc/cpuinfo | sort -u | head -1)
[[ -n "$cpuinfo" ]] && ok "extension materielle de virtualisation : $cpuinfo" || ko "ni vmx ni svm dans /proc/cpuinfo"

echo "== D. Outils du pipeline =="
for t in crosvm mkfs.erofs mksquashfs qemu-img cargo rustc; do
  command -v "$t" >/dev/null 2>&1 && ok "$t : $(command -v $t)" || ko "outil manquant : $t (etapes build/image)"
done

echo "== E. Session hote heritee des Jalons 3/4 =="
[[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wayland-0" ]] \
  && ok "socket Exo actif : \${XDG_RUNTIME_DIR}/wayland-0" \
  || ko "pas de socket wayland-0 — lancer la session Ash avant le Jalon 5"

echo; echo "check-kernel-config : $PASS OK / $FAIL KO"
exit $(( FAIL > 0 ))
