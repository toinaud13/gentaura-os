#!/usr/bin/env bash
# ============================================================================
# GentAura - Jalon 2 : orchestrateur idempotent du build Chromium-Ash fenêtré
# Étapes : check -> fetch -> patch -> config -> build -> test (-> all)
# Reprenable après interruption ; chaque étape est safe à relancer.
#
# Variables d'env :
#   BUILD_ROOT   (défaut ~/gentaura-build)     racine du checkout
#   OUT_DIR      (défaut out/GentAuraDev)      dossier gn relatif à src/
#   NINJA_JOBS   (défaut auto, bridé si RAM < 32 Go)
#   SKIP_FETCH / SKIP_BUILD pour aller au smoke-test sur build existant
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$HOME/gentaura-build}"
SRC="$BUILD_ROOT/src"
OUT_DIR="${OUT_DIR:-out/GentAuraDev}"
MODE="${1:-all}"

export PATH="/opt/depot_tools:${PATH}"
command -v fetch >/dev/null || command -v gclient >/dev/null \
  || { echo "ERREUR : depot_tools absent du PATH (/opt/depot_tools). Cf README §2." >&2; exit 1; }

log() { echo -e "\n\033[1;36m==> [$(date +%H:%M:%S)] $*\033[0m"; }

st_check()  { log "Pré-vol machine (RAM/disque/noyau/outils)"; "$SCRIPT_DIR/check-kernel-config.sh"; }

st_fetch()  {
  log "Checkout Chromium (base Ash/Aura/Exo ~70 Go)"
  if [[ -d "$SRC/.git" ]]; then
    log "Checkout déjà présent -> sync uniquement"
    ( cd "$SRC" && git checkout . && rm -f ../.gclient_entries ) || true
    ( cd "$BUILD_ROOT" && gclient sync --with_branch_heads --nohooks )
  else
    mkdir -p "$SRC" && cd "$SRC"
    fetch --nohooks chromium
    cd "$SRC"
  fi
  # Hooks indispensables à la cible chromeos (cros_system_api, etc.)
  ( cd "$SRC" && ./build/install-build-deps.sh --chrome-root="$BUILD_ROOT" ) \
    || log "WARN: install-build-deps non compatible Gentoo -> emerge deps-chromeos.conf manuellement"
}

st_patch()  {
  log "Application des 3 patchs stratégiques (fuzz-mode + verrou marqueurs)"
  "$SCRIPT_DIR/apply-gentaura-patches.sh" apply
  "$SCRIPT_DIR/apply-gentaura-patches.sh" check
}

st_config() {
  log "Configuration GN (args.gn.dev prototype)"
  mkdir -p "$SRC/$OUT_DIR"
  cp "$SCRIPT_DIR/args.gn.dev" "$SRC/$OUT_DIR/args.gn"
  ( cd "$SRC" && gn gen "$OUT_DIR" )
  log "Récapitulatif des flags ozone/exo :"
  ( cd "$SRC" && gn args --short "$OUT_DIR" 2>/dev/null | grep -E 'ozone|exo|cras|vaapi' ) || true
}

st_build()  {
  local ram jobs
  ram=$(awk '/MemTotal/{print int($2/1048576)}' /proc/meminfo)
  jobs="${NINJA_JOBS:-$(nproc)}"
  # Bridage anti-OOM au link lld (cf. piège n°2 du README)
  (( ram < 32 && jobs > 4 )) && jobs=4 && log "RAM ${ram} Go < 32 -> ninja bridé à -j $jobs"
  log "Compilation de chrome + ash (-j $jobs) — 4 à 8 h attendues"
  ( cd "$SRC" && autoninja -C "$OUT_DIR" chrome ash )
}

st_test()   {
  log "Smoke test : Ash+Exo en fenêtre + client foot sur le socket Exo"
  [[ -x "$SRC/$OUT_DIR/chrome" ]] || { echo "ERREUR : binaire absent — lancer 'build' d'abord." >&2; exit 1; }
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  local before after
  before=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | sort)
  "$SRC/$OUT_DIR/chrome" --ozone-platform=wayland --ash-test-mode \
        --user-data-dir=/tmp/gentaura-dev-profile \
        > /tmp/gentaura-ash.log 2>&1 &
  local pid=$!
  for _ in $(seq 1 30); do
    after=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | sort)
    [[ "$after" != "$before" ]] && break
    sleep 1
  done
  newsock=$(comm -13 <(echo "$before") <(echo "$after") | head -1)
  if [[ -n "$newsock" ]]; then
    log "Socket Exo détecté : $newsock — lancement de foot comme client natif"
    WAYLAND_DISPLAY="$(basename "$newsock")" setsid foot &
    sleep 3
    if grep -q "exo: wayland socket ready" /tmp/gentaura-ash.log; then
      log "*** MARQUEUR PATCH 01 PRÉSENT — JALON 2 : Exo expose bien \$XDG_RUNTIME_DIR ***"
    else
      log "WARN : socket créé mais marqueur sd_notify du patch 01 absent du log"
    fi
    log "Validez VISUELLEMENT la fenêtre foot dans Ash, puis Ctrl+C ici."
    wait $pid
  else
    tail -40 /tmp/gentaura-ash.log
    echo "ÉCHEC : aucun nouveau socket Wayland créé par Exo." >&2; exit 1
  fi
}

case "$MODE" in
  check)  st_check ;;
  fetch)  st_fetch ;;
  patch)  st_patch ;;
  config) st_config ;;
  build)  st_build ;;
  test)   st_test ;;
  all)    st_check; st_fetch; st_patch; st_config; st_build; st_test ;;
  *) echo "Usage: $0 [check|fetch|patch|config|build|test|all]" >&2; exit 2 ;;
esac
log "Étape '$MODE' terminée."
