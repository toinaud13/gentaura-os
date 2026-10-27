# GentAura — Stratégie BINHOST (Jalon 2/3)

Le monolithe `chromium-ash` est **le goulot d'étranglement absolu** du projet :

| Ressource | Minimum requis pour compiler | Sur la machine cible GentAura |
|---|---|---|
| RAM | **32 Go** (ou 16 Go + 32 Go swap ZRAM/NVMe) | ne compile **jamais** |
| Disque `/var/tmp/portage` | **~80 Go** | reçoit uniquement le `.gpkg.tar` |
| Temps | plusieurs heures (lld final link) | **quelques secondes** (téléchargement) |

## Flux de travail

1. **Serveur BINHOST** (machine la plus puissante) :
   `binhost-sync.sh publish` → `emerge chromium-ash` + `quickpkg`.
2. **Machine cible** :
   `binhost-sync.sh install` → `emerge -gK gentaura-base/chromium-ash`.

Les paquets passerelles (`gentaura-bridge`, `gentaura-app-scanner`, `sommelier`)
sont des micro-démons Rust/C légers : ils peuvent être compilés localement.
