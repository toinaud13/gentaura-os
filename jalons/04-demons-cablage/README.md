# Jalon 4 — Câblage des démons (`gentaura-bridge` & `gentaura-app-scanner`)

Objectif (roadmap TDD Section 6.4) : faire vivre les jauges Ash (Wi-Fi, batterie,
séance) sur les services Gentoo standards, et injecter les applications natives
`.desktop` dans la Shelf/App List via l'IPC du patch 03.

## Prérequis (Jalons 1–3 validés)
- Socle Gentoo systemd + Mesa/PipeWire/NetworkManager (J1)
- Binaire `chromium-ash` avec les 3 patchs appliqués et vérifiés (J2/J3)
- Session Ash bare-metal Ozone-DRM opérationnelle (J3)
- Machine de build Rust : `dev-lang/rust` + `cargo` (ou cross-compilation BINHOST)

## Contenu du kit
| Fichier | Rôle |
|---|---|
| `run-stage4.sh` | Orchestrateur idempotent : `check → build → install → smoke → status` |
| `smoke-bridge.sh` | Preuve contractuelle D-Bus : compare chaque interface exposée par le pont à sa cible Gentoo réelle (NM, UPower, logind) |
| `validate-stage4.sh` | Definition of Done automatique (5 checks, cf. ci-dessous) |

## Procédure
```bash
cd gentaura-os/jalons/04-demons-cablage
sudo ./run-stage4.sh all          # ou étape par étape : check build install smoke
./validate-stage4.sh              # en tant qu'utilisateur de session (scanner côté user)
```

## Definition of Done (Jalon 4)
1. **Pont vivant** : `gentaura-bridge` actif, les 3 noms `org.chromium.*` acquis sur le bus système, `Type=dbus` satisfait.
2. **Batterie réelle** : la jauge Ash affiche le % provenant d'UPower (relayé par le pont), pas un stub 100 %.
3. **Wi-Fi réel** : le panneau network d'Ash liste les SSIDs (scan relayé vers NetworkManager/iwd) ; `RequestScan()` déclenche un vrai `nmcli device wifi rescan`.
4. **Session directe** : Ash démarre sans écran de connexion (pont renvoie `SESSION_STARTED`, cohérent avec le patch 02).
5. **Shelf native** : les apps `.desktop` de Gentoo apparaissent dans l'App List avec un `aura_app_id` préfixé `gentaura:` ; un clic lance l'app dans `app-gentaura-<id>.scope` avec `WAYLAND_DISPLAY=wayland-0` et **sans** `DISPLAY`.

## Vérification manuelle (outils `gdbus` de glib)
```bash
# Côté pont (bus système) :
gdbus call --system --dest org.chromium.PowerManager --object-path /org/chromium/PowerManager \
  --method org.chromium.PowerManager.GetPowerSupplyProperties
gdbus call --system --dest org.chromium.flimflam --object-path /org/chromium/flimflam/Manager \
  --method org.chromium.flimflam.Manager.RequestScan
# Côté scanner (bus de session, après login graphique) :
journalctl --user -u gentaura-app-scanner -b | grep 'registered into Ash App List'
systemctl --user list-units 'app-gentaura-*'   # scopes créés au clic
```

## Exemple de sortie attendue (smoke-bridge)
```
== A. Noms bus système acquis par le pont ==
  ✔ nom acquis : org.chromium.flimflam
  ✔ nom acquis : org.chromium.PowerManager
  ✔ nom acquis : org.chromium.SessionManager
...
== RÉSULTAT : 12 ✔ / 0 ✘ ==
```

## Pièges connus
- **Double nom flimflam** : si un vieux `chromeos-session` est encore installé, il entre en conflit pour `org.chromium.flimflam` → `systemctl mask chromeos-*` avant l'étape `install`.
- **Ordre de démarrage** : le pont DOIT être `Before=gentaura-shell.service` (déclaré dans son unité) ; sinon Ash fige sur l'écran de chargement réseau.
- **Scanner côté user** : `gentaura-app-scanner.service` est une unité *utilisateur* (`systemctl --user enable`) — ne pas l'activer en système, il n'aurait ni `XDG_RUNTIME_DIR` ni accès au bus de session patché 03.
- **Zombie dbus name** : après redémarrage du pont, `BusName=` + `Restart=on-failure` suffisent ; ne pas mettre `Type=simple` (course avec Ash).
