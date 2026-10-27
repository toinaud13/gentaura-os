# Jalon 2 — Prototypage Chromium-Ash en mode fenêtré (hôte de dev / BINHOST)

> **Objectif (TDD Section 6, Jalon 2)** : valider la chaîne de compilation
> `target_os = "chromeos"` avec la toolchain système Gentoo, produire un binaire
> `chrome` capable de lancer **Ash + Aura + Exo**, et vérifier que le socket
> Wayland d'Exo accepte un terminal natif (`foot`) — **sans toucher au bare-metal**
> (mode fenêtré sous le bureau existant de la machine de dev).

---

## 1. Prérequis de la machine BINHOST / dev

| Ressource | Minimum | Vérification |
|---|---|---|
| RAM | **32 Go** (ou 16 Go + 32 Go swap ZRAM/NVMe) | `free -h` |
| Disque `/var/tmp/portage` | **80 Go** libres (idéalement tmpfs NVMe ou disque dédié) | `df -h /var/tmp/portage` |
| CPU | 8 cœurs min. (compilation ~4–8 h) | `nproc` |
| Kernel | ≥ 6.6 avec les options du contrat (`CONFIG_USER_NS`, `CONFIG_UDMABUF`) | `check-kernel-config.sh` |
| GPU | Mesa fonctionnelle avec EGL/GLESv2/Vulkan (le prototype s'affiche via le compositeur du bureau hôte) | `es2_info` / `vulkaninfo --summary` |

```bash
# Swap ZRAM si seulement 16 Go de RAM :
emerge -au sys-apps/zram-tools && zramctl /dev/zram0 --size 32G --algorithm zstd
swapon /dev/zram0
```

## 2. Installation de la toolchain depot-tools

```bash
# depot_tools n'est plus packagé par Gentoo ; installation via le dépôt amont :
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git \
    /opt/depot_tools
echo 'export PATH="/opt/depot_tools:${PATH}"' >> /etc/profile.d/depot_tools.sh
source /etc/profile.d/depot_tools.sh

# Dépendances système pour le checkout + build ChromeOS (voir deps-chromeos.conf)
emerge -au $(grep -v '^#' deps-chromeos.conf | tr '\n' ' ')
```

## 3. Automatisation complète (recommandée)

Le script `run-stage2-build.sh` enchaîne checkout → patchs → args.gn → gn gen → ninja
→ smoke test. Il est **idempotent** (peut être relancé après interruption) :

```bash
mkdir -p ~/gentaura-build && cd ~/gentaura-build
~/gentaura-os/jalons/02-chromium-ash-dev/run-stage2-build.sh all 2>&1 | tee stage2.log
```

Étapes individuelles disponibles : `fetch | patch | config | build | test`.

## 4. Détail des étapes (compréhension / debug manuel)

### 4.1 Checkout de la base 132.0 (cible Ash/Aura/Exo)
```bash
mkdir -p ~/gentaura-build/src && cd ~/gentaura-build/src
fetch --nohooks chromium          # ~70 Go téléchargés (gclient + depot cache)
cd src
./build/install-build-deps.sh --chrome-root=$HOME/gentaura-build
```

### 4.2 Application des 3 patchs stratégiques
Les patchs vivent dans l'overlay (`gentaura-base/chromium-ash/files/`).
Ils sont appliqués en fuzz-mode (numéros de ligne indicatifs, cf. en-têtes) :
```bash
~/gentaura-os/jalons/02-chromium-ash-dev/apply-gentaura-patches.sh apply
```
- `01-exo-xdg-runtime-socket.patch` → socket `$XDG_RUNTIME_DIR/wayland-0` + `sd_notify READY=1`
- `02-local-unix-session-bypass.patch` → bypass OOBE/cryptohome (non requis en mode fenêtré, posé pour validation)
- `03-shelf-freedesktop-launcher.patch` → IPC `gentaura:` pour l'app-scanner

### 4.3 Configuration GN
`args.gn` = celui de l'overlay, **plus** deux overrides propres au prototypage
(à retirer au Jalon 3 pour repasser en DRM pur) :
```gn
ozone_platform_wayland = true     # PROTOTYPE ONLY : Ash se connecte au compositeur du bureau hôte
is_component_build = false        # sinon la cible ash n'est pas produite en standalone
custom_toolchain="//build/toolchain/linux/unbundle:default"   # toolchain système Gentoo
proprietary_codecs = true
ffmpeg_branding = "Chrome"
```

### 4.4 Compilation
```bash
gn gen out/GentAuraDev
ninja -C out/GentAuraDev chrome ash            # cible `ash` = shell Ash/Aura/Exo
# ~4-8 h sur 8 cores / 32 GB. lld exige les 32 GB au moment du link final.
```

### 4.5 Smoke test Exo ← terminal natif (Definition of Done)
```bash
XDG_RUNTIME_DIR=/run/user/$(id -u) ./out/GentAuraDev/chrome \
    --ozone-platform=wayland --ash-test-mode &   # Ash+Exo démarrent sous le WM hôte
WAYLAND_DISPLAY=$(ls $XDG_RUNTIME_DIR/wayland-* | tail -1) foot
```

## 5. Definition of Done — Jalon 2

Validée par `validate-stage2.sh` (auto-check) :

- [ ] `out/GentAuraDev/chrome` existe, linked avec `lld`, taille > 200 Mo
- [ ] Les 3 patchs GentAura sont présents dans l'arbre (reverse-apply check OK)
- [ ] Le processus Ash expose un socket Wayland dans `$XDG_RUNTIME_DIR`
- [ ] `foot` (ou `weston-terminal`) ouvre une fenêtre **dans le compositor Exo d'Ash**
      (vérif : `wayland-info` listant `wl_compositor` fourni par Exo)
- [ ] Log de démarrage contient `exo: wayland socket ready` (marqueur du patch 01)

## 6. Publication BINHOST (optionnel ici, requis Jalon 3)

Une fois le prototype validé, l'ebuild `chromium-ash` rejoue exactement ces args
en `src_compile` ; `binhost-sync.sh publish` produit le `.gpkg.tar`
pour la cible. Voir `docs/BINHOST.md`.

## 7. Pièges connus (retour d'expérience ChromeOS-on-Linux / Fyde)

1. **`is_chromeos_device=false` + toolchain système** : utiliser
   `custom_toolchain="//build/toolchain/linux/unbundle:default"` dans args.gn
   (sinon téléchargement clang interne ~6 Go et conflits libc++).
2. **Link OOM** : si `ld.lld` est tué (exit 137), ajouter
   `ldflags=["-Wl,--reduce-memory-overheads"]`, activer `-j 4` et monter le ZRAM.
3. **Hooks manquants** : `install-build-deps.sh` ne connaît pas Gentoo →
   utiliser `deps-chromeos.conf` + emerge des équivalents.
4. **Dépôt `chromeos` absent du checkout vanilla** : la pile Ash/Exo vit dans
   `//ash` et `//components/exo` (présents dans tout checkout Chromium ≥ 100) ;
   les composants spécifiques `//third_party/cros_system_api` sont récupérés
   automatiquement par `fetch` quand `target_os="chromeos"` est passé en hook.
