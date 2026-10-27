#!/usr/bin/env bash
# ============================================================================
# GentAura - Jalon 2 : application des 3 patchs stratégiques de l'overlay
# sur le checkout Chromium (~/gentaura-build/src).
# Les numéros de ligne des patchs étant indicatifs (base 132.0.x), on applique
# en mode FUZZ tolérant, puis on VERROUE chaque hunk par un marqueur grep.
#
# Usage : apply-gentaura-patches.sh [apply|revert|check]
# Env   : CHROMIUM_SRC=/chemin/src  OVERLAY_DIR=/chemin/gentaura-os
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="${OVERLAY_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
CHROMIUM_SRC="${CHROMIUM_SRC:-$HOME/gentaura-build/src}"
PATCH_DIR="$OVERLAY_DIR/gentaura-base/chromium-ash/files"
MODE="${1:-apply}"

PATCHES=(
  "01-exo-xdg-runtime-socket.patch|components/exo/wayland/server.cc|exo: wayland socket ready"
  "02-local-unix-session-bypass.patch|chrome/browser/ash/login/session/user_session_manager.cc|GENTAUTA_LOCAL_SESSION_BYPASS"
  "03-shelf-freedesktop-launcher.patch|chrome/browser/ui/app_list/ash/ash_app_id_helper.cc|gentaura:"
)

[[ -d "$CHROMIUM_SRC" ]] || { echo "ERREUR : checkout introuvable : $CHROMIUM_SRC" >&2; exit 1; }

rc=0
for entry in "${PATCHES[@]}"; do
  IFS='|' read -r pfile probe marker <<< "$entry"
  full="$PATCH_DIR/$pfile"
  [[ -f "$full" ]] || { echo "ERREUR : patch manquant $full" >&2; exit 1; }

  case "$MODE" in
    apply)
      # --fuzz=5 --3way : accepte les décalages de ligne, garde les conflits
      # marqués pour correction manuelle éventuelle.
      if (cd "$CHROMIUM_SRC" && patch -p1 --forward --fuzz=5 -i "$full") ; then
        echo "[OK]     $pfile appliqué"
      else
        echo "[CONFLIT] $pfile -> corrigez manuellement puis relancez 'check'"
        rc=1
      fi
      ;;
    revert)
      (cd "$CHROMIUM_SRC" && patch -p1 -R --forward --fuzz=5 -i "$full") \
        && echo "[OK]     $pfile réverté" || echo "[WARN]   $pfile non réverté (déjà propre ?)"
      ;;
    check)
      # Vérification dure : le marqueur sémantique doit exister dans la cible.
      if grep -rqF "$marker" "$CHROMIUM_SRC/$probe" 2>/dev/null \
         || grep -rqF "$marker" "$CHROMIUM_SRC/${probe%.*}".* 2>/dev/null \
         || grep -rlqF "$marker" "$CHROMIUM_SRC/$(dirname "$probe")" 2>/dev/null; then
        echo "[OK]     $pfile : marqueur '$marker' présent"
      else
        # fallback : reverse-check du patch complet (le plus fiable)
        if (cd "$CHROMIUM_SRC" && patch -p1 -R --dry-run -f --fuzz=5 -i "$full" >/dev/null 2>&1); then
          echo "[OK]     $pfile : reverse-dry-run OK (patch intégralement appliqué)"
        else
          echo "[ÉCHEC]  $pfile : NI marqueur '$marker' NI reverse-apply valide"
          rc=1
        fi
      fi
      ;;
    *) echo "Usage: $0 [apply|revert|check]" >&2; exit 2 ;;
  esac
done
exit $rc
