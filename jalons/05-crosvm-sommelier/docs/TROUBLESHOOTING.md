# Jalon 5 — Dépannage du pipeline crosvm → Sommelier → Exo

## #virgl — La fenêtre de la VM apparaît mais reste noire / crash GL
**Symptôme** : `crosvm` loggue `rutabaga: virgl_renderer_init failed` ou sommelier
segfault au premier frame.
**Cause n°1** : désaccord de **version majeure de `virglrenderer`** entre hôte et
invité. Le protocole cross-domain négocie VIRGL_VERSION; une divergence casse tout.
```bash
# Hôte :
qlist -Iv media-libs/virglrenderer   # ex : 2.4.0
# Invité (via journal VM ou rebuild image) : doit être >= version hôte, même majeure.
```
**Correctif** : reconstruire l'image invitée (`stage5-image.sh`) avec le paquet
`sommelier`+`virglrenderer` synchronisés depuis le même BINHOST.

## #vhost-access — EACCES sur /dev/vhost-vsock au lancement
`crosvm run ... --vsock cid=3,device=/dev/vhost-vsock` échoue `Permission denied`.
→ Règle udev `systemd/60-gentaura-crosvm.rules` non installée OU utilisateur hors
groupe `vhost`.
```bash
sudo ./scripts/install-udev-rules.sh   # copie regle + udevadm reload
getent group vhost kvm                 # verifier membres
```

## #cpu-fallback — CPU de crosvm à 100 % pendant qu'une app animée tourne dans la VM
Preuve que le chemin **blob/copy** est utilisé au lieu du cross-domain DMABUF :
1. Vérifier le CLI : `--gpu context-types=cross-domain:virgl2` présent (sinon repli
   virgl2 simple = copies CPU). 
2. Vérifier `CONFIG_UDMABUF=y` sur l'hôte (`check-kernel-config.sh`).
3. Vérifier que l'invité monte bien `/dev/dri/renderD128` virtio :
   `ls /dev/dri` dans la VM → `virtio_gpu` absent ⇒ module `drm_virtio_gpu` manquant
   dans le noyau invité (ajouter au bzImage ou initramfs).

## #squashfs-ro — systemd invité refuse de booter sur rootfs SquashFS read-only
Comportement attendu : systemd a besoin d'écritures (/run, /var/lib). Solutions :
- Utiliser l'image **ext4 `--rw`** produite par défaut par `stage5-image.sh` ;
- Ou montage `erofs` ro + **overlayfs tmpfs** en invité (`rootflags=X-mountoptions`),
  variante COULD HAVE "mise à jour atomique" du PRD.

## #no-window — Rien n'apparaît dans Ash alors que la VM tourne
- `WAYLAND_DISPLAY` côté invité pointé vers le socket **virtio** créé par sommelier,
  pas celui de l'hôte (jamais accessible directement). Dans la VM : `echo $WAYLAND_DISPLAY`
  doit renvoyer `wayland-0` fourni par **sommelier**, et `ps` doit montrer sommelier actif.
- Côté hôte : le `--wayland-sock` doit pointer `$XDG_RUNTIME_DIR/wayland-0` créé par le
  patch 01 (`exo-xdg-runtime-socket`). Vérifier : `ls -l $XDG_RUNTIME_DIR/wayland-0`.

## #cid-conflict — Deux VMs => `cid=3` déjà alloué
Chaque instance `gentaura-crosvm@<nom>` DOIT avoir un CID unique : passer par
`Environment=GENTAUTRA_CID=` différent (2=locale hôte, 3=réservé TERMINT/bridge).
Voir `man vsock` section CID allocation.
