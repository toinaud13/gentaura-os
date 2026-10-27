#!/usr/bin/env bash
# ============================================================================
# GentAura - Jalon 2 : Definition of Done (auto-vérification post-build)
# À lancer sur la machine de build, après run-stage2-build.sh build.
# Usage : validate-stage2.sh [chemin/src]   (défaut ~/gentaura-build/src)
# ============================================================================
set -uo pipefail
SRC="${1:-$HOME/gentaura-build/src}"
OUT_DIR="${OUT_DIR:-out/GentAuraDev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; TOTAL=5

check() { # $1 libellé ; $2 commande -> 0 = OK
  TOTAL_N=$((PASS+1))
  if eval "$2" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  [$(($PASS+0))/$TOTAL] OK   — $1"
  else echo "  [--/$TOTAL]      ÉCHEC — $1"; fi
}

echo "== Validation Jalon 2 : prototypage Chromium-Ash fenêtré =="

# DoD 1 : binaire chrome présent, link lld, taille > 200 Mo
check "binaire chrome > 200 Mo" \
  "[[ -f '$SRC/$OUT_DIR/chrome' ]] && (( \$(stat -c%s '$SRC/$OUT_DIR/chrome') > 200*1024*1024 ))"

# DoD 2 : les 3 patchs stratégiques sont dans l'arbre (marqueurs sémantiques)
check "3 patchs GentAura appliqués (apply-gentaura-patches.sh check)" \
  "'$SCRIPT_DIR/apply-gentaura-patches.sh' check"

# DoD 3 : args.gn conforme (ozone drm compilé, X11 banni, CRAS désactivé)
check "args.gn : ozone_platform_x11=false + use_cras=false + target_os chromeos" \
  "grep -q 'ozone_platform_x11 = false' '$SRC/$OUT_DIR/args.gn' && grep -q 'use_cras = false' '$SRC/$OUT_DIR/args.gn' && grep -q 'target_os = \"chromeos\"' '$SRC/$OUT_DIR/args.gn'"

# DoD 4 : le binaire embarque bien Exo (symboles wayland server du composant)
check "symboles exo::wayland présents dans le binaire (Exo compilé comme serveur)" \
  "nm -D '$SRC/$OUT_DIR/chrome' 2>/dev/null | grep -qi 'exo' || strings '$SRC/$OUT_DIR/chrome' | grep -qi 'compositor-exo'"

# DoD 5 : pas de dépendance runtime X11 obligatoire (WON'T HAVE PRD)
check "aucune liaison directe à libX11 en NEEDED (X11 banni côté Ash)" \
  "! readelf -d '$SRC/$OUT_DIR/chrome' 2>/dev/null | grep -q 'libX11.so'"

echo "---------------------------------------------------------"
if (( PASS == TOTAL )); then
  echo "*** JALON 2 VALIDÉ ($PASS/$TOTAL) ***"
  echo "Reste la validation HUMAINNE du smoke test :"
  echo "  run-stage2-build.sh test  -> fenêtre 'foot' rendue par le socket Exo d'Ash"
  exit 0
else
  echo "*** JALON 2 INCOMPLET ($PASS/$TOTAL) — corriger les échecs ci-dessus ***"
  exit 1
fi
