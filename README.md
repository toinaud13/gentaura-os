# GentAura (anciennement *FedAura*)

> Mini-distribution Linux ultra-performante, modulaire et souveraine :
> châssis **Gentoo (`systemd`)** + tableau de bord **Ash/Aura/Exo** (ChromeOS)
> + coffre-fort d'isolation matérielle **`crosvm`**.
> *« Une Formule 1 homologuée pour la route. »*

Ce dépôt est à la fois un **overlay Portage standard** (`masters = gentoo`) et
le fournisseur des micro-démons passerelles décrits dans le dossier
d'architecture :

* 📄 **[docs/PRD.md](docs/PRD.md)** — Product Requirements Document (vision, proposition de valeur, MoSCoW, KPIs)
* 📄 **[docs/TDD.md](docs/TDD.md)** — Spécification Technique d'Implémentation (contrat noyau, args.gn, patchs C++, démons, pipeline crosvm, jalons)

## Arborescence

```
gentaura-os/
├── metadata/layout.conf                 # Declaration overlay Portage
├── profiles/
│   ├── repo_name                        # "gentaura"
│   └── default/linux/amd64/23.0/aura/   # Profil systeme (make.defaults, packages, package.use)
├── kernel/
│   └── gentaura.config                  # Contrat noyau (UDMABUF / KVM / CGROUPS / PSI...)
├── gentaura-base/
│   ├── chromium-ash/                    # Ebuild maitre Aura/Ash/Exo + args.gn + 3 patchs C++
│   │   └── files/
│   │       ├── args.gn
│   │       ├── 01-exo-xdg-runtime-socket.patch
│   │       ├── 02-local-unix-session-bypass.patch
│   │       ├── 03-shelf-freedesktop-launcher.patch
│   │       └── binhost-sync.sh          # Stratgie BINHOST (32Go RAM / 80Go disque)
│   ├── gentaura-bridge/                 # Demon D-Bus Rust (flimflam/power/session -> NM/UPower/logind)
│   ├── gentaura-session/                # Unites systemd user, slice cgroups, greetd/PAM
│   └── gentaura-app-scanner/            # Indexeur .desktop -> Ash Shelf (inotify + systemd-run)
├── dev-util/
│   ├── crosvm-aura/                     # Ebuild crosvm optimise Rutabaga/PipeWire + pipeline Zero-Copy
│   └── sommelier/                       # Proxy Wayland/X11 pour VMs invitees
└── docs/
    ├── PRD.md                           # Product Requirements Document
    ├── TDD.md                           # Spec technique d'implementation
    └── BINHOST.md                       # Repartition compilation lourde
```

## Activation de l'overlay

```sh
cat > /etc/portage/repos.conf/gentaura.conf <<EOF
[gentaura]
location = /var/db/repos/gentaura
sync-type = git
sync-uri = https://github.com/gentaura/gentaura-os.git
auto-sync = yes
EOF
eselect profile list   # -> choisir default/linux/amd64/23.0/aura
emerge -av @gentaura-core
```

## Démarrage rapide par jalons

| Jalon | Objectif | Validation |
|---|---|---|
| **1** | Socle Gentoo + noyau contrat (`merge_config.sh` avec `kernel/gentaura.config`) | TTY < 3 s, zéro X11, Mesa/PipeWire/NM OK |
| **2** | Prototypage Chromium-Ash fenêtré sur le BINHOST | socket `$XDG_RUNTIME_DIR/wayland-0`, `foot` se connecte |
| **3** | Bare-metal Ozone-DRM + `gentaura-shell.service` (Type=notify, `OOMScoreAdjust=-900`) | Ash plein écran KMS, libinput OK |
| **4** | Démons `gentaura-bridge` + `gentaura-app-scanner` | jauges Wi-Fi/batterie live, apps Gentoo dans la Shelf |
| **5** | `crosvm --gpu context-types=cross-domain:virgl2 --wayland-sock=…` + `sommelier` | fenêtre VM projetée en zero-copy dans Exo |

⚠️ **Point de vigilance (stress-test final)** : ne jamais compiler
`chromium-ash` sur la machine cible — voir [docs/BINHOST.md](docs/BINHOST.md).

## KPIs internes (exigences non-fonctionnelles)

- Cold boot → bureau Ash interactif : **< 6 s** (NVMe)
- RAM à froid (Ash+Exo+systemd+socle) : **< 650 Mo**
- Affichage : direct scanout `dma-buf`, 60–144 Hz sans tearing
- Résilience : saturation CPU/RAM d'une app ou VM ⇒ aucune frame perdue sur le curseur

*Hors périmètre strict : aucun Xorg hôte, aucun compte/télémétrie Google, aucune Enterprise Enrollment.*
