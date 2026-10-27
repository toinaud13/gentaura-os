# GentAura — TDD (Spécification Technique d'Implémentation)

> Complément technique du [PRD.md](PRD.md). Chaque section ci-dessous est
> directement tracée vers les artefacts versionnés de ce dépôt.

## 1. Architecture du Dépôt et de l'Overlay Portage

Toute l'intelligence de construction de **GentAura** est encapsulée dans un dépôt
Git maître structuré comme un **Overlay Gentoo standard** couplé aux définitions
des démons passerelles :

```
gentaura-os/
├── profiles/
│   ├── repo_name                        # Identifiant : "gentaura"
│   └── default/linux/amd64/23.0/aura/   # Le Profil Système GentAura
│       ├── make.defaults                # USE flags globaux (-X wayland ozone-drm...)
│       ├── packages                     # Paquets du système de base
│       └── package.use                  # Flags spécifiques par paquet
├── gentaura-base/
│   ├── chromium-ash/                    # L'ebuild maître compilant Aura/Ash/Exo
│   │   ├── chromium-ash-132.0.ebuild
│   │   └── files/                       # Patchs C++ (Bypass Cryptohome, Socket Exo)
│   ├── gentaura-bridge/                 # Le démon traducteur D-Bus (Shill/Powerd -> Linux)
│   ├── gentaura-session/                # Les unités systemd, PAM et scripts d'environnement
│   └── gentaura-app-scanner/            # Synchroniseur /usr/share/applications -> Ash Shelf
└── dev-util/
    ├── crosvm-aura/                     # Ebuild crosvm optimisé Rutabaga/PipeWire
    └── sommelier/                       # Proxy Wayland/X11 pour les VMs invitées
```

## 2. Spécification du Noyau Linux (Contrat Kernel)

Le noyau Gentoo (`sys-kernel/gentoo-kernel`) doit être compilé avec le fragment
de configuration strict [`kernel/gentaura.config`](../kernel/gentaura.config)
pour supporter simultanément **Ozone-DRM** en *bare-metal* et **crosvm** en
*Zero-Copy* :

```
# --- SOUS-SYSTÈME GRAPHIQUE (OZONE-DRM & EXO) ---
CONFIG_DRM=y
CONFIG_DRM_KMS_HELPER=y
CONFIG_UDMABUF=y                  # CRITIQUE : Partage mémoire zéro-copie Hôte <-> Exo
CONFIG_DMA_SHARED_BUFFER=y
CONFIG_SYNC_FILE=y                # Synchronisation explicite Vulkan/Wayland (Explicit Sync)
# CONFIG_FB_DEVICE is not set     # On désactive le vieux framebuffer hérité

# --- HYPERVISEUR & TUNNELS CROSVM (PHASE 2) ---
CONFIG_VIRTUALIZATION=y
CONFIG_KVM=y
CONFIG_KVM_INTEL=m                # (ou CONFIG_KVM_AMD=m)
CONFIG_VHOST_VSOCK=m              # Canal de communication ultra-rapide Hôte <-> VM
CONFIG_VIRTIO_GPU=m               # Support invité Rutabaga Cross-Domain

# --- ISOLATION & RÉSILIENCE (SYSTEMD & SANDBOX CHROMIUM) ---
CONFIG_CGROUPS=y
CONFIG_MEMCG=y
CONFIG_PSI=y                      # Pressure Stall Information (Arbitrage RAM Ash/crosvm)
CONFIG_USER_NS=y                  # Indispensable pour le sandbox de Chromium
CONFIG_SECCOMP=y
```

Fusion de la config : `scripts/kconfig/merge_config.sh -m old.config kernel/gentaura.config`

## 3. Spécification de Compilation du Monolithe (`chromium-ash`)

Cœur nucléaire du projet. L'ebuild
[`gentaura-base/chromium-ash/chromium-ash-132.0.ebuild`](../gentaura-base/chromium-ash/chromium-ash-132.0.ebuild)
injecte la configuration GN suivante ([`files/args.gn`](../gentaura-base/chromium-ash/files/args.gn)) :

```
# 1. CIBLE ARCHITECTURALE : Activer la pile Aura/Ash/Exo
target_os = "chromeos"
is_chromeos_device = false        # Permet d'utiliser la toolchain système Gentoo
use_ozone = true

# 2. BACKEND MATÉRIEL : Parler directement au noyau (KMS/GBM)
ozone_auto_platforms = false
ozone_platform = "drm"
ozone_platform_drm = true
ozone_platform_headless = true
ozone_platform_x11 = false        # Banni
ozone_platform_wayland = false    # Ash EST le serveur Wayland (via Exo), pas un client

# 3. PILOTES GRAPHIQUES & MULTIMÉDIA
use_egl = true
use_vaapi = true                  # Décodage matériel vidéo (Intel/AMD)
enable_vulkan = true
use_system_libdrm = true
use_system_minigbm = true         # Allocation des tampons graphiques GBM

# 4. SERVICES SYSTÈME & AUDIO (Raccordement au socle Gentoo)
use_cras = false                  # On désactive le serveur audio Google CRAS...
use_alsa = true                   # ...au profit de PipeWire-ALSA / Pulse
use_pulseaudio = true
use_cups = false                  # Mini-distro : pas de démon d'impression lourd
use_kerberos = false
```

### Les 3 Patchs C++ Stratégiques (dossier `files/` de l'ebuild)

Pour éviter que le binaire `chrome` compilé avec `target_os = "chromeos"` ne se
comporte comme s'il était enfermé sur un Chromebook commercial, trois adaptations
chirurgicales sont appliquées à l'étape `src_prepare()` :

1. **[`01-exo-xdg-runtime-socket.patch`](../gentaura-base/chromium-ash/files/01-exo-xdg-runtime-socket.patch)**
   (`components/exo/wayland/server.cc`)
   * *Origine :* Exo crée son socket dans `/run/chrome/wayland-0`.
   * *Modification :* Alignement sur la norme Freedesktop
     `$XDG_RUNTIME_DIR/wayland-0` (soit `/run/user/1000/wayland-0`) et notification
     `sd_notify("READY=1")` à `systemd` dès que le socket écoute.
2. **[`02-local-unix-session-bypass.patch`](../gentaura-base/chromium-ash/files/02-local-unix-session-bypass.patch)**
   (`ash/login/` & `chrome/browser/ash/login/`)
   * *Origine :* Ash affiche l'OOBE exigeant Wi-Fi + compte Google et monte un coffre `cryptohome`.
   * *Modification :* Session locale directe forcée
     (`--login-user=$USER --login-profile=user --user-data-dir=/home/$USER/.config/gentaura-shell`),
     ouverture de session déléguée en amont à `systemd-logind` / `greetd` (PAM).
3. **[`03-shelf-freedesktop-launcher.patch`](../gentaura-base/chromium-ash/files/03-shelf-freedesktop-launcher.patch)**
   (`chrome/browser/ui/app_list/`)
   * *Origine :* Le lanceur Ash n'affiche que extensions Chrome, PWA et apps Crostini (`garcon`).
   * *Modification :* Point d'entrée IPC local permettant à **`gentaura-app-scanner`**
     d'enregistrer les applications natives Gentoo (`.desktop`) et de les lancer via
     `systemd-run --user --scope`.

## 4. Spécification des Démons Passerelles (Contrats d'Interfaces)

Plutôt que les démons lourds Google (`shill`, `powerd`), deux micro-démons
ultra-légers écrits en **Rust** :

### A. Le Pont D-Bus Système : `gentaura-bridge`

S'enregistre sur le bus système D-Bus sous les noms exacts attendus par le code
C++ d'Ash (`chromeos/ash/components/dbus/`) et traduit les appels vers les
services Gentoo standards — voir
[`gentaura-base/gentaura-bridge/src/main.rs`](../gentaura-base/gentaura-bridge/src/main.rs).

```
CONTRAT D'INTERFACE : gentaura-bridge (Démon Système)

[Interface exposée à Ash]                 [Action interne]              [Cible Gentoo]
------------------------------------------------------------------------------------------
org.chromium.flimflam.Manager       <---> Traduction des états    <---> org.freedesktop.NetworkManager
  - GetProperties()                       Wi-Fi, force du signal,         (ou net.connman.iwd)
  - RequestScan()                         adresses IP et DNS.

org.chromium.PowerManager           <---> Conversion des niveaux  <---> org.freedesktop.UPower
  - GetPowerSupplyProperties()            de batterie (%) et des        & org.freedesktop.login1
  - RequestSuspend()                      ordres de mise en veille.       (systemd-logind)

org.chromium.SessionManagerInterface <--> Simulation de l'état    <---> Validation immédiate :
  - RetrieveSessionState()                "SESSION_STARTED" pour        L'utilisateur est déjà
  - EmitLoginPromptVisible()              débloquer le bureau Ash.      authentifié par PAM.
```

### B. L'Indexeur d'Applications : `gentaura-app-scanner`

Pont entre les paquets Linux (Portage / Flatpak) et le **Shelf / App Launcher**
d'Ash — voir
[`gentaura-base/gentaura-app-scanner/src/main.rs`](../gentaura-base/gentaura-app-scanner/src/main.rs).

1. Surveille via `inotify` `/usr/share/applications/` et `~/.local/share/applications/`.
2. Parse chaque `.desktop` (Nom, Icône SVG/PNG, `Exec=`, Catégorie).
3. Convertit l'entrée en descripteur d'application externe Exo (`aura_app_id`).
4. Au clic dans Ash, exécute l'application avec `WAYLAND_DISPLAY=wayland-0`,
   `GDK_BACKEND=wayland` / `QT_QPA_PLATFORM=wayland` dans une tranche Cgroup
   dédiée (`app-gentaura-*.scope`).

## 5. Architecture de la Phase 2 : Pipeline `crosvm` + `Sommelier`

Chaîne technique exacte de [`dev-util/crosvm-aura`](../dev-util/crosvm-aura/crosvm-aura-132.0.ebuild)
et [`dev-util/sommelier`](../dev-util/sommelier/sommelier-132.0.ebuild) :

```
[ VM INVITÉE (Kernel Linux Minimal en mémoire) ]
  1. L'application (ex: App X11 ou App lourde) dessine sa fenêtre.
  2. [Sommelier] (Démon invité lancé avec --virtio-gpu --wayland-channel=/dev/dri/renderD128)
     encapsule les requêtes Wayland ET les références de buffers GPU dans des commandes Virtio.
                                        |
                         (Hypercall KVM / Virtio-GPU)
                                        v
[ HÔTE GENTOO (Processus crosvm) ]
  3. [crosvm] est lancé avec le paramètre :
     --gpu context-types=cross-domain:virgl2 --wayland-sock=${XDG_RUNTIME_DIR}/wayland-0
  4. Le moteur [Rutabaga GFX] de crosvm extrait le canal Wayland et les descripteurs DMABUF
     et les transmet directement au socket local d'[Exo].
                                        |
                         (Zéro copie mémoire CPU !)
                                        v
[ COMPOSITEUR ASH / EXO ]
  5. [Exo] reçoit la surface, lit le tampon directement dans la VRAM du GPU hôte,
     et [Ash] dessine les ombres et la barre de titre Aura autour de la fenêtre de la VM !
```

## 6. Plan d'Exécution et Jalons (Roadmap Technique)

1. **Jalon 1 — Forge du Socle Gentoo & Noyau Cible :** Gentoo minimal
   `default/linux/amd64/23.0/systemd` ; noyau fusionné avec
   `kernel/gentaura.config` (`UDMABUF`, `DRM`, `KVM`, `CGROUPS`) ; Mesa (`egl
   gles2 vulkan wayland`), PipeWire, NetworkManager. Validation : TTY pur < 3 s,
   zéro composant X11.
2. **Jalon 2 — Prototypage Chromium-Ash fenêtré (hôte de dev/BINHOST) :**
   `target_os = "chromeos"`, compilation de validation, vérification qu'un
   terminal natif (`foot`, `weston-terminal`) se connecte au socket Exo.
3. **Jalon 3 — Déploiement Bare-Metal (Ozone-DRM) & unité systemd :** empaquetage
   `ozone_platform = "drm"` dans l'overlay ; `gentaura-shell.service`
   (Type=notify, délégation logind/greetd, `OOMScoreAdjust=-900`) ; Ash plein
   écran KMS + libinput.
4. **Jalon 4 — Câblage des Démons :** `gentaura-bridge` (jauges batterie/Wi-Fi)
   et `gentaura-app-scanner` (apps `.desktop` dans le lanceur Ash).
5. **Jalon 5 — Hyperviseur Graphique (Phase 2) :** ebuilds `crosvm` (rutabaga_gfx,
   pipewire) et `sommelier` ; image racine invitée SquashFS ; application isolée
   (Wayland et X11) projetée en Zero-Copy dans Exo.

---

> **Point de vigilance du Stress-Test Final (Ressources de Compilation) :**
> La compilation de `chromium-ash` (Jalons 2/3) exige ≥ **32 Go de RAM** (ou 16 Go
> + 32 Go de swap ZRAM/NVMe) et ≈ **80 Go** dans `/var/tmp/portage`. Déporter
> impérativement la compilation sur la machine la plus puissante configurée en
> **Serveur BINHOST Gentoo** : la cible GentAura n'a plus qu'à télécharger le
> `.gpkg.tar` — voir [BINHOST.md](BINHOST.md).
