#!/bin/sh
# ============================================================================
# GentAura - Pipeline Zero-Copy crosvm + Sommelier (TDD Partie 2, Section 5)
#
#   [VM invitee] sommelier --virtio-gpu --wayland-channel=/dev/dri/renderD128
#        |  (Virtio-GPU cross-domain / hypercall KVM)
#   [Hote] crosvm --gpu context-types=cross-domain:virgl2 \
#              --wayland-sock=${XDG_RUNTIME_DIR}/wayland-0 ...
#        |  (Rutabaga GFX extrait canal Wayland + descripteurs DMABUF)
#   [Exo/Ash] lit le tampon directement en VRAM hote -> zero copie CPU !
# ============================================================================
set -eu

GENTAUTRA_IMG="${GENTAUTRA_IMG:-/var/lib/gentaura/vm/rootfs.squashfs}"
MEM="${GENTAUTRA_MEM:-2G}"
CPUS="${GENTAUTRA_CPUS:-4}"

exec crosvm run \
	--rw \
	--disk-path "${GENTAUTRA_IMG}" \
	--socket "/run/gentaura/crosvm-root" \
	--vsock "cid=3,device=/dev/vhost-vsock" \
	--mem "${MEM}" \
	--cpus "${CPUS}" \
	--net "tap=false,mac=9a:57:1a:b6:8e:4f" \
	--balloon \
	--rng \
	--gpu \
	"context-types=cross-domain:virgl2" \
	"rutabaga-gfx=true" \
	--wayland-sock="${XDG_RUNTIME_DIR}/wayland-0" \
	"shared-memory-dir=${XDG_RUNTIME_DIR}/gentaura-dmabuf" \
	--log-level debug

# NOTE cote invite (image SquashFS du Jalon 5) :
#   sommelier --virtio-gpu --xwl --wayland-display=wayland-0 &
#   XWayland isole ne vit QUE dans la VM (WON'T HAVE PRD : pas de X sur l'hote).
