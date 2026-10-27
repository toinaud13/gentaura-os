# GentAura — PRD (Product Requirements Document)

> Document de référence du produit. Version 1.0 — vérifié par stress-test architectural.
> Ancien nom de code : *FedAura*.

## 1. Vision et Objectif du Produit

* **Nom de code :** **GentAura**
* **Vision :** Créer une mini-distribution Linux ultra-performante, modulaire et
  souveraine, mariant la puissance d'optimisation à la source de **Gentoo Linux
  (`systemd`)** avec la fluidité graphique et l'ergonomie du bureau **Aura / Ash /
  Exo** de Google, complétée par l'isolation matérielle de **`crosvm`**.
* **Analogie directrice :** Construire une *Formule 1 homologuée pour la route* :
  le châssis et le moteur sont forgés sur mesure par Gentoo (zéro surpoids,
  compilé au scalpel), le tableau de bord et le pilotage assisté viennent de
  ChromeOS (Ash/Aura/Exo), et le coffre-fort blindé de transport est assuré par
  `crosvm`.

## 2. Proposition de Valeur (Pourquoi GentAura ?)

| Problème Actuel | Approche ChromeOS Standard | Approche Linux Classique (KDE/GNOME) | Approche **GentAura** |
| --- | --- | --- | --- |
| **Contrôle de l'OS Hôte** | Verrouillé (Rootfs en lecture seule, prison Google). | Total, mais pile graphique fragmentée. | **Total** (Portage + `systemd` natif) avec l'UI unifiée d'Ash. |
| **Exécution des Apps Linux** | Lente au démarrage (enfermée de force dans la VM Crostini). | Native, mais sans le compositeur Aura/Exo. | **Hybride au choix :** Native directe sur Exo **OU** isolée dans `crosvm`. |
| **Vie Privée & Compte** | Compte Google Cloud et télémétrie obligatoires. | Comptes Unix locaux standards. | **100 % Local (PAM / Unix)**, déverrouillé de `cryptohome`. |
| **Empreinte Système** | Lourde (Services Android/Google imposés). | Moyenne à lourde (Dépendances X11/Wayland mixtes). | **Chirurgicale** (`USE="-X"`, Wayland pur, binaires optimisés). |

## 3. Périmètre Fonctionnel (Matrice MoSCoW)

### MUST HAVE (Incontournables — Phase 1 : Socle Bare-Metal)

* Démarrage direct du binaire **Chromium-Ash** sur le métal via **Ozone-DRM**
  (sans serveur X11 ni compositeur tiers).
* Exposition du serveur Wayland **Exo** (`$XDG_RUNTIME_DIR/wayland-0`) aux
  applications natives de l'espace utilisateur Gentoo.
* Authentification locale standard (utilisateur Unix `/home/$USER`)
  court-circuitant le verrouillage Cloud Google.
* Démon passerelle (**`gentaura-bridge`**) traduisant les appels D-Bus système
  d'Ash vers `NetworkManager`/`iwd`, `UPower` et `PipeWire`.
* Indexeur automatique (**`gentaura-app-scanner`**) injectant les fichiers
  `.desktop` de Gentoo dans le lanceur d'applications (*App List* / *Shelf*) d'Ash.

### SHOULD HAVE (Attendus — Phase 2 : Virtualisation `crosvm`)

* Intégration de **`crosvm`** avec accélération GPU **Zero-Copy**
  (`rutabaga_gfx` / `virtio-gpu` en mode *cross-domain*).
* Intégration du compositeur mandataire **`sommelier`** dans l'image invitée pour
  projeter les fenêtres des VMs (y compris X11 via XWayland isolé) directement
  dans Exo sur l'hôte.
* Distribution binaire via un serveur **Gentoo BINHOST** pour éviter la
  compilation de Chromium sur les machines clientes.

### COULD HAVE (Optionnels — Phase 3 : Écosystème Étendu)

* Intégration d'Android en conteneur/VM (Waydroid ou ARCVM via `crosvm`) raccordé
  nativement à Exo.
* Système de mise à jour atomique optionnel par images SquashFS/Btrfs snapshots.

### WON'T HAVE (Hors périmètre strict)

* **Aucun serveur Xorg / X11** sur le système hôte Gentoo (XWayland est
  strictement relégué à l'intérieur des sandboxes `crosvm`).
* Aucune dépendance aux serveurs d'authentification ou de gestion de flotte
  (Enterprise Enrollment) de Google.

## 4. Exigences Non-Fonctionnelles (KPIs & SLA Internes)

* **Temps de démarrage (Cold Boot -> Bureau Ash interactif) :** Moins de
  **6 secondes** sur SSD NVMe.
* **Empreinte RAM à froid (Ash + Exo + systemd + Services Socle) :** Inférieure à
  **650 Mo**.
* **Latence d'affichage Wayland (Exo Direct Scanout) :** **60 à 144 Hz** constants
  sans déchirement (*tearing*), transfert de buffers par descripteurs `dma-buf`
  uniquement.
* **Résilience (Isolation Cgroups v2) :** Une saturation CPU/RAM à 100 % par une
  application native ou une VM `crosvm` ne doit provoquer aucune perte de *frame*
  sur le curseur et les animations d'Aura.

## 5. Traçabilité PRD → Artefacts du Dépôt

| Exigence PRD | Artefact d'implémentation |
|---|---|
| Ash bare-metal via Ozone-DRM | `gentaura-base/chromium-ash/files/args.gn` (`ozone_platform = "drm"`), `gentaura-session/gentaura-shell.service` |
| Socket Exo standard Freedesktop | Patch `files/01-exo-xdg-runtime-socket.patch` |
| Auth 100 % locale (PAM/logind) | Patch `files/02-local-unix-session-bypass.patch`, `gentaura-session/greeter.conf` |
| Apps Gentoo dans la Shelf | Patch `files/03-shelf-freedesktop-launcher.patch`, démon `gentaura-app-scanner` |
| Pont D-Bus shill/powerd simulés | Démon `gentaura-bridge` (flimflam / PowerManager / SessionManager) |
| Résilience cgroups v2 | `gentaura-session/app-gentaura.slice`, scopes `app-gentaura-*.scope` |
| Zero-copy crosvm (Phase 2) | `dev-util/crosvm-aura` + `files/launch-crosvm-aura.sh`, `dev-util/sommelier` |
| Empreinte chirurgicale | `profiles/default/linux/amd64/23.0/aura/make.defaults` (`USE="-X wayland ozone-drm"`) |
| Distribution binaire | `docs/BINHOST.md`, `gentaura-base/chromium-ash/files/binhost-sync.sh` |
