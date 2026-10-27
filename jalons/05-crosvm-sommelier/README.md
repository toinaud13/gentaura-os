# Jalon 5 — Activation de l'Hyperviseur Graphique (crosvm + Sommelier, Phase 2)

Objectif TDD Section 5 & 6.5 : ouvrir une application **isolée dans une VM `crosvm`**
(Wayland natif ET X11 via XWayland cloisonné en invité) et la voir projetée
**Zero-Copy** (descripteurs DMABUF, sans copie CPU) dans le serveur Wayland **Exo**
de l'hôte GentAura, avec décorations Aura dessinées par Ash.

```
[VM invitee]  app -> sommelier --virtio-gpu (Virtio-GPU cross-domain)
      |  hypercall KVM / DMABUF
[Hote]        crosvm --gpu context-types=cross-domain:virgl2 --wayland-sock=$XDG_RUNTIME_DIR/wayland-0
      |  Rutabaga GFX extrait canal Wayland + memfds
[Exo/Ash]     lit le buffer en VRAM hote -> compose la fenetre VM  <-- Zero copie !
```

## Prérequis (héritage Jalons 1–4)
| Élément | Vérification |
|---|---|
| Contrat noyau J1 complet Phase 2 | `check-kernel-config.sh` : `KVM(_INTEL/_AMD)=m`, `VHOST_VSOCK=m`, `VIRTIO_GPU(m)`, `UDMABUF=y`, `SYNC_FILE=y` |
| Session Ash + socket Exo (J3/J4) | `$XDG_RUNTIME_DIR/wayland-0` présent, `gentaura-shell` actif |
| Droits hyperviseur | utilisateur dans `kvm,vhost` + subuid/subgid ≥ 65536 |
| Outils | `qemu-img`, `mkfs.erofs` (ou mksquashfs), `cargo`, `modprobe` OK |

## Arborescence du kit
```
jalons/05-crosvm-sommelier/
├── README.md                        # ce fichier
├── run-stage5.sh                    # orchestrateur idempotent : check -> build -> image -> launch -> smoke
├── validate-stage5.sh               # Definition of Done (6 checks)
├── scripts/
│   ├── check-kernel-config.sh       # pré-vol noyau Phase 2 (+ remédiation modprobe)
│   ├── build-crosvm-aura.sh         # crosvm features rutabaga-gfx+virgl+cross-domain+pipewire
│   ├── build-sommelier.sh           # sommelier + xwl (XWayland invité uniquement)
│   └── smoke-zero-copy.sh           # preuve zero-copy : dmabuf_count/handle ++, pas de blit CPU
├── guest-overlay/                   # surcouche minimal ISO : make.defaults + paquets invité
│   └── etc/portage/{make.defaults,package.use}
├── systemd/
│   ├── gentaura-crosvm@.service     # unité user : 1 VM = 1 scope cgroup app-gentaura-*
│   └── 60-gentaura-crosvm.rules     # udev kvm/vhost-vsock/renderD128 (mode 0660, groupes)
└── docs/TROUBLESHOOTING.md          # pièges connus (virgl version, vhost access mode, squashfs ro…)
```

## Procédure

### A. Sur la machine de build (BINHOST recommandée)
```bash
./run-stage5.sh check    # pré-vol noyau/outils/droits
./run-stage5.sh build    # compile crosvm-aura + sommelier (~15 min, Rust pur)
./run-stage5.sh image    # construit rootfs invité : stage3 -> rsync -> genkernel --bootdir
                         # -> erofs/squashfs + kernel bzImage dans /var/lib/gentaura/vm/
```

### B. Sur la cible GentAura (session Ash active)
```bash
sudo ./scripts/install-udev-rules.sh        # udev + groupes kvm/vhost
./run-stage5.sh launch                       # systemctl --user start gentaura-crosvm@demo
./scripts/smoke-zero-copy.sh                 # ouvre foot + xterm( عبر xwl) dans la VM
./validate-stage5.sh                         # DoD 6 checks
```

### C. Lancement manuel (équivalent de `launch-crosvm-aura.sh`)
```bash
crosvm run \
  --rw --disk-path /var/lib/gentaura/vm/rootfs.img \
  --vsock cid=3,device=/dev/vhost-vsock \
  --mem 2G --cpus 4 --net tap=false,mac=9a:57:1a:b6:8e:4f \
  --gpu "context-types=cross-domain:virgl2,rutabaga-gfx=true,shared-memory-dir=${XDG_RUNTIME_DIR}/gentaura-dmabuf" \
  --wayland-sock="${XDG_RUNTIME_DIR}/wayland-0" \
  --balloon --rng
# coté invité (systemd dans l'image) :
#   sommelier --virtio-gpu --xwl --wayland-display=wayland-0 &
#   WAYLAND_DISPLAY=wayland-0 GDK_BACKEND=wayland foot        # cas Wayland
#   DISPLAY=:0 xterm                                          # cas X11 -> XWayland ISOLÉ (WON'T HAVE hôte respecté)
```

## Definition of Done (validate-stage5.sh)
1. Kernel + modules KVM/VHOST_VSOCK/VIRTIO_GPU chargés, `/dev/kvm` accessible.
2. VM démarre en < 3 s (boot kernel direct PVH/bzImage) et répond sur vsock CID=3.
3. Fenêtre applicative visible côté Ash (`weston-info`/scrot region ou journal Exo `dmabuf`).
4. **Preuve zero-copy** : compteur `dmabuf` d'Exo incrémenté, zéro `memcpy` virtio-gpu blob dans le perf crosvm.
5. Cas X11 validé en invité, **sans** aucun process Xorg sur l'hôte (`pgrep -x Xorg` vide).
6. Audio PipeWire traversant le canal virtio (optionnel, warning si absent).

## Pièges documentés (voir docs/TROUBLESHOOTING.md)
- `virglrenderer` hôte/invité **même version majeure** sinon crash GL.
- `/dev/vhost-vsock` : groupe + mode 0660 sinon EACCES au boot VM.
- Image invitée : kernel en **bzImage externe** (`--kernel`) car squashfs ro ne permet pas un kobj-init complet ; initramfs minimal avec modules virtio.
- `--socket /run/gentaura/crosvm-root` pour le control-plane (stop propre via `crosvm stop`).
