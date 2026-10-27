# Jalon 1 — Forge du socle Gentoo & noyau cible

Objectif (PRD/TDD §6.1) : Gentoo `default/linux/amd64/23.0/systemd` minimal,
demarrant en **TTY pur en < 3 s**, sans **aucun** composant X11, avec Mesa
(egl gles2 vulkan wayland), PipeWire et NetworkManager valides.

## VM de test recommandee (Virtio-GPU)
```bash
qemu-system-x86_64 -enable-kvm -cpu host -smp 8 -m 16G \
  -drive if=virtio,file=gentaura.qcow2 \
  -device virtio-gpu-pci -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -cdrom install-amd64-minimal.iso -boot d -nographic
```
(`-device virtio-gpu-pci` prefigure le chemin DRM/KMS utilise ensuite en bare-metal.)

## Procedure
1. **Boot LiveCD** (Install Gentoo ou SystemRescue), partitionne (GPT : ESP 512M + root), formate, monte `/mnt/gentoo` (+ `/mnt/gentoo/boot`).
2. Copie ce dossier sur la RAM du live (`cp jalons/01-socle-gentoo/*.sh /mnt/gentoo/root/`) puis :
   ```bash
   ./install-stage1-chroot.sh https://bouncer.gentoo.org/fetch/root/all gentaura-vm alice Europe/Paris
   enter_chroot
   ./configure-chroot.sh gentaura-vm alice Europe/Paris   # emerge socle + noyau (contrat fusionne + verrouille)
   passwd ; passwd alice                                  # mots de passe
   grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GENTaura
   grub-mkconfig -o /boot/grub/grub.cfg
   exit ; umount -R /mnt/gentoo ; reboot
   ```
3. **Definition of Done** : sur le systeme boote, `./validate-stage1.sh` doit afficher `*** JALON 1 VALIDE ***`.

## Points d'attention
- `VIDEO_CARDS` et `CPU_FLAGS_X86` dans make.conf : ajuste a ton vrai materiel (`cpuid2cpuflags`).
- Le fragment noyau `kernel.config` (= `../../kernel/gentaura.config`) est fusionne par `merge_config.sh` puis **verrouille** : le script echoue si une option critique (UDMABUF, PSI, USER_NS…) manque.
- Les units systemd GentAura (shell, bridge, scanner) seront installees au **Jalon 3/4** via l'overlay `gentaura-base/*` ; ici on valide uniquement le socle.
