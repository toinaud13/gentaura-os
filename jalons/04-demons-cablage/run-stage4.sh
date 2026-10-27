#!/usr/bin/env bash
# =============================================================================
# Jalon 4 — Câblage des démons gentaura-bridge & gentaura-app-scanner
# Orchestrateur idempotent : check -> build -> install -> smoke -> status
# Relançable après toute interruption (chaque étape est vérifiable séparément).
# =============================================================================
set -euo pipefail

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$STAGE_DIR/../.." && pwd)"
BRIDGE_SRC="$REPO_ROOT/gentaura-base/gentaura-bridge"
SCANNER_SRC="$REPO_ROOT/gentaura-base/gentaura-app-scanner"
BUILD_OUT="${GENTAURA_STAGE4_OUT:-$HOME/.cache/gentaura/stage4}"
TARGET_USER="${SUDO_USER:-$(whoami)}"
TARGET_UID="$(id -u "$TARGET_USER")"

log()  { printf '\n\033[1;36m[stage4]\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32m✔\033[0m %s\n' "$*"; }
ko()   { printf '  \033[1;31m✘\033[0m %s\n' "$*"; }
die()  { ko "$*"; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "outil manquant : $1"; }

# -----------------------------------------------------------------------------
step_check() {
  log "Étape 1/5 — Pré-vol Jalon 4 (dépendances de build + héritage J1–J3)"
  need_cmd cargo; need_cmd rustc; need_cmd systemctl; need_cmd gdbus
  ok "cargo $(cargo --version | awk '{print $3}') / rustc $(rustc --version | awk '{print $2}')"

  # Héritage Jalon 1 : socle systemd + services cibles du pont.
  for svc in NetworkManager upower dbus; do
    systemctl is-active "$svc" >/dev/null 2>&1 \
      && ok "service système actif : $svc" \
      || die "service requis inactif : $svc (Jalon 1 non validé ?)"
  done

  # Héritage Jalon 3 : binaire Ash patché présent et session définie.
  ASH_BIN="${GENTAURA_ASH_BIN:-/opt/gentaura/chrome}"
  [[ -x "$ASH_BIN" ]] && ok "binaire Ash : $ASH_BIN" \
    || die "Ash introuvable ($ASH_BIN) — valider d'abord le Jalon 3, ou exporter GENTAURA_ASH_BIN"

  # Contrat noyau minimal pour les scopes systemd-run du scanner.
  [[ -r /proc/$$/cgroup ]] && grep -q '^0::/' /proc/$$/cgroup \
    && ok "cgroups v2 unifié (indispensable aux app-gentaura-*.scope)" \
    || die "cgroups v2 absent — relire kernel/gentaura.config (CONFIG_CGROUPS)"

  # Anti-conflit : aucun démon Google ne doit briguer org.chromium.*
  if gdbus call --system --dest org.freedesktop.DBus --object-path /org/chromium/Dbus \
       --method org.freedesktop.DBus.ListNames 2>/dev/null | grep -q 'org.chromium'; then
    log "ATTENTION : des noms org.chromium.* sont déjà pris sur le bus système."
    log "  → masquer les restes ChromeOS : systemctl mask chromeos-session shill powerd"
  fi
  ok "pré-vol OK"
}

# -----------------------------------------------------------------------------
step_build() {
  log "Étape 2/5 — Compilation release des deux micro-démons Rust"
  mkdir -p "$BUILD_OUT"
  for crate in "$BRIDGE_SRC" "$SCANNER_SRC"; do
    name="$(basename "$crate")"
    if [[ -x "$BUILD_OUT/$name" ]]; then
      ok "$name déjà construit (skippé, relancer avec 'clean' pour rebuild)"
      continue
    fi
    log "cargo build --release : $name"
    ( cd "$crate" && cargo build --release --target-dir "$BUILD_OUT/target" )
    cp "$BUILD_OUT/target/release/$name" "$BUILD_OUT/$name"
    ok "$name → $BUILD_OUT/$name"
  done
}

# -----------------------------------------------------------------------------
step_install() {
  log "Étape 3/5 — Installation des binaires et unités systemd"
  [[ $EUID -eq 0 ]] || die "step_install requiert sudo"

  install -Dm755 "$BUILD_OUT/gentaura-bridge"        /usr/bin/gentaura-bridge
  install -Dm755 "$BUILD_OUT/gentaura-app-scanner"   /usr/bin/gentaura-app-scanner
  ok "binaires dans /usr/bin"

  install -Dm644 "$BRIDGE_SRC/gentaura-bridge.service" \
    /usr/lib/systemd/system/gentaura-bridge.service
  ok "unité système : gentaura-bridge.service (Type=dbus, Before=gentaura-shell)"

  # Le scanner est une unité UTILISATEUR (bus de session + XDG_RUNTIME_DIR).
  install -Dm644 "$SCANNER_SRC/gentaura-app-scanner.service" \
    "/usr/lib/systemd/user/gentaura-app-scanner.service"
  ok "unité utilisateur : gentaura-app-scanner.service (Slice=app-gentaura.slice)"

  # Tranche cgroups dédiée (si absente du déploiement J3).
  local slice="/usr/lib/systemd/system/app-gentaura.slice"
  [[ -f "$slice" ]] || cat > "$slice" <<'UNIT'
[Unit]
Description=GentAura native application slice (isolation RAM/CPU des apps Shelf)
Slice=.slice
[Slice]
MemoryHigh=4G
CPUWeight=100
UNIT
  ok "slice : app-gentaura.slice"

  systemctl daemon-reload
  systemctl enable --now gentaura-bridge.service
  ok "gentaura-bridge activé (démarré)"

  # Enable user-unit pour l'utilisateur de session GentAura.
  runuser -u "$TARGET_USER" -- loginctl enable-linger "$TARGET_USER" 2>/dev/null || true
  su - "$TARGET_USER" -c "XDG_RUNTIME_DIR=/run/user/$TARGET_UID systemctl --user enable gentaura-app-scanner" \
    && ok "scanner enabled pour $TARGET_USER" \
    || ko "scanner : à activer après la première session graphique (--user enable)"
}

# -----------------------------------------------------------------------------
step_smoke() {
  log "Étape 4/5 — Smoke test contractuel (délégation à smoke-bridge.sh)"
  bash "$STAGE_DIR/smoke-bridge.sh"
}

# -----------------------------------------------------------------------------
step_status() {
  log "Étape 5/5 — État des lieux"
  systemctl status gentaura-bridge.service --no-pager -n 5 || true
  echo "--- noms org.chromium.* acquis ---"
  gdbus call --system --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.ListNames | tr ',' '\n' | grep -o 'org\.chromium\.[A-Za-z]*' | sort -u
  echo "--- journaux scanner (user $TARGET_USER) ---"
  journalctl --user -u gentaura-app-scanner -n 10 -o cat --no-pager \
    -M "${TARGET_USER}@" 2>/dev/null \
    || su - "$TARGET_USER" -c "journalctl --user -u gentaura-app-scanner -n 10 -o cat --no-pager" || true
}

step_clean() {
  log "Nettoyage des artefacts de build"
  rm -rf "$BUILD_OUT"; ok "$BUILD_OUT supprimé"
}

case "${1:-all}" in
  check)   step_check ;;
  build)   step_build ;;
  install) step_install ;;
  smoke)   step_smoke ;;
  status)  step_status ;;
  clean)   step_clean ;;
  all)     step_check; step_build; step_install; step_smoke; step_status ;;
  *) die "usage: $0 {check|build|install|smoke|status|clean|all}" ;;
esac
log "run-stage4.sh terminé ($(date -Is))"
