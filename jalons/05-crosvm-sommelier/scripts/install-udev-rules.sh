#!/usr/bin/env bash
# Installation des regles udev + groupes du Jalon 5 (idempotent, sudo requis).
set -euo pipefail
SUDO="${SUDO:-sudo}"
$SUDO install -Dm644 "$(dirname "$0")/../systemd/60-gentaura-crosvm.rules" /etc/udev/rules.d/60-gentaura-crosvm.rules
for g in kvm vhost render; do getent group "$g" >/dev/null || $SUDO groupadd -r "$g"; done
U="${SUDO_USER:-$(whoami)}"
for g in kvm vhost render; do getent group "$g" | grep -q ":$U\$" || $SUDO usermod -aG "$g" "$U"; done
$SUDO modprobe kvm-intel 2>/dev/null || $SUDO modprobe kvm-amd 2>/dev/null || true
$SUDO modprobe vhost_vsock 2>/dev/null || true
printf 'kvm\nvhost_vsock\nvirtio_net\n' | $SUDO tee /etc/modules-load.d/gentaura-vm.conf >/dev/null
$SUDO udevadm control --reload && $SUDO udevadm trigger
echo "[udev] OK — relancer la session (reboot ou re-login) pour les nouveaux groupes."
